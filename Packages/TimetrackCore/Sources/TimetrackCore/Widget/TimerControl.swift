import Foundation

/// What a lock-screen / Live Activity / widget button asks for.
public enum TimerControlAction: Sendable, Equatable {
    case start
    /// Pause is a normal pause: the running segment is stopped (the gap stays a real pause, nothing is invented).
    case pause
    /// Weiter: starts a new segment of the paused kind.
    case resume
    case stop
}

/// How the pause marker changes.
public enum PauseMarkerChange: Sendable, Equatable {
    case keep
    case set(PauseMarker)
    case clear
}

/// Pure plan for one button press: what goes into the offline queue and what the app shows meanwhile. The same
/// `TimerActionQueue` as the app and the Focus filter delivers it (idempotent via the action id), so a press without network is
/// not lost and a late delivery is corrected back to the press time.
public struct TimerControlPlan: Sendable, Equatable {
    public enum Ignored: Sendable, Equatable { case alreadyRunning, notRunning, nothingToResume }

    /// Nil when nothing has to be sent (an ignored press, or stopping an already paused day).
    public var queued: QueuedTimerAction?
    public var marker: PauseMarkerChange
    /// The snapshot with the action applied (optimistic), nil for an ignored press.
    public var snapshot: WidgetSnapshot?
    public var ignored: Ignored?

    public var isApplied: Bool { ignored == nil }
}

public enum TimerControl {
    public static func plan(_ action: TimerControlAction, snapshot: WidgetSnapshot?, marker stored: PauseMarker?,
                            now: Date = .now, eventId: UUID = UUID()) -> TimerControlPlan {
        let running = snapshot?.isRunning == true
        let marker = PauseMarker.current(stored, running: running, at: now)
        func send(_ command: QueuedTimerAction.Command, _ change: PauseMarkerChange) -> TimerControlPlan {
            let queued = QueuedTimerAction(id: eventId, command: command, queuedAt: now)
            return TimerControlPlan(queued: queued, marker: change, snapshot: (snapshot ?? .empty).applying(queued), ignored: nil)
        }
        func ignore(_ reason: TimerControlPlan.Ignored, clearing change: PauseMarkerChange = .keep) -> TimerControlPlan {
            TimerControlPlan(queued: nil, marker: change, snapshot: nil, ignored: reason)
        }

        switch action {
        case .start:
            return running ? ignore(.alreadyRunning) : send(.start(.work), .clear)
        case .pause:
            guard running, let snapshot else { return ignore(.notRunning) }
            return send(.stop, .set(PauseMarker(kind: snapshot.kind, pausedAt: now)))
        case .resume:
            if running { return ignore(.alreadyRunning, clearing: .clear) }
            guard let marker else { return ignore(.nothingToResume) }
            return send(.start(marker.kind), .clear)
        case .stop:
            if running { return send(.stop, .clear) }
            // Stopping a paused day: the segment is already stopped, only the pause ends (activity goes away).
            if marker != nil { return TimerControlPlan(queued: nil, marker: .clear, snapshot: snapshot, ignored: nil) }
            return ignore(.notRunning, clearing: .clear)
        }
    }
}

extension WidgetSnapshot {
    /// The snapshot as it will look once `action` is delivered (same rules as `TodayDisplay.applying`, plus the segment list).
    public func applying(_ action: QueuedTimerAction) -> WidgetSnapshot {
        var result = self
        result.updatedAt = action.queuedAt
        switch action.command {
        case .start(let kind):
            result.isRunning = true
            result.kind = kind
            result.startedAt = action.queuedAt
            var list = result.segments ?? []
            list.append(WidgetSegment(kind: kind, startedAt: action.queuedAt, endedAt: nil))
            result.segments = Array(list.suffix(Self.maxSegments))
        case .stop:
            if isRunning, let start = startedAt {
                if todaySeconds(at: action.queuedAt) != nil { result.todaySeconds += max(0, Int(action.queuedAt.timeIntervalSince(start))) }
                if var list = result.segments, let last = list.indices.last, list[last].endedAt == nil {
                    list[last].endedAt = action.queuedAt
                    result.segments = list
                }
            }
            result.isRunning = false
            result.startedAt = nil
        }
        return result
    }
}
