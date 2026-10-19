import SwiftUI

/// One arc of a `SegmentedRing`. Hatched arcs are drawn as radial stripes, so they differ from solid arcs by pattern and not by colour alone.
public struct RingSegment: Identifiable, Sendable {
    public let id: String
    public let fraction: Double
    public let tint: Color
    public let hatched: Bool

    public init(id: String, fraction: Double, tint: Color, hatched: Bool = false) {
        self.id = id
        self.fraction = fraction
        self.tint = tint
        self.hatched = hatched
    }
}

/// Ring made of consecutive arcs (starting at 12 o'clock) on a faint track, e.g. vacation: booked solid, planned hatched, rest free.
public struct SegmentedRing<Center: View>: View {
    private let segments: [RingSegment]
    private let lineWidth: CGFloat
    private let trackTint: Color
    private let accessibilityText: Text
    private let center: Center
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(segments: [RingSegment], lineWidth: CGFloat = 12, trackTint: Color, accessibilityText: Text, @ViewBuilder center: () -> Center = { EmptyView() }) {
        self.segments = segments
        self.lineWidth = lineWidth
        self.trackTint = trackTint
        self.accessibilityText = accessibilityText
        self.center = center()
    }

    /// Start and end of every arc as fractions of the full circle; empty and non-finite fractions are skipped and the sum is capped at 1.
    public static func arcs(for fractions: [Double]) -> [(start: Double, end: Double)] {
        var cursor = 0.0
        var result: [(Double, Double)] = []
        for raw in fractions {
            let value = raw.isFinite ? min(max(raw, 0), 1 - cursor) : 0
            result.append((cursor, cursor + value))
            cursor += value
        }
        return result
    }

    public var body: some View {
        let arcs = Self.arcs(for: segments.map(\.fraction))
        ZStack {
            Circle().stroke(trackTint.opacity(0.14), lineWidth: lineWidth)
            ForEach(Array(zip(segments, arcs)), id: \.0.id) { segment, arc in
                if arc.end > arc.start {
                    Arc(start: arc.start, end: arc.end, hatched: segment.hatched, lineWidth: lineWidth, tint: segment.tint)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.6), value: arc.end)
                }
            }
            center
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private struct Arc: View {
        let start: Double
        let end: Double
        let hatched: Bool
        let lineWidth: CGFloat
        let tint: Color

        var body: some View {
            Circle()
                .trim(from: start, to: end)
                .stroke(hatched ? AnyShapeStyle(tint) : AnyShapeStyle(tint.gradient),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt, dash: hatched ? [2.2, 3.2] : []))
                .rotationEffect(.degrees(-90))
                .background {
                    // A hatched arc keeps a faint fill so a short arc stays visible between the stripes.
                    if hatched {
                        Circle().trim(from: start, to: end).stroke(tint.opacity(0.22), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)).rotationEffect(.degrees(-90))
                    }
                }
        }
    }
}

/// Legend marker that mirrors the ring: a solid dot for solid arcs, a striped dot for hatched ones.
public struct RingLegendSwatch: View {
    private let tint: Color
    private let hatched: Bool
    private let isTrack: Bool

    public init(tint: Color, hatched: Bool = false, isTrack: Bool = false) {
        self.tint = tint
        self.hatched = hatched
        self.isTrack = isTrack
    }

    public var body: some View {
        ZStack {
            if isTrack {
                Circle().strokeBorder(tint.opacity(0.5), lineWidth: 1.5)
            } else if hatched {
                Circle().fill(tint.opacity(0.22))
                Circle().inset(by: 1.5).stroke(tint, style: StrokeStyle(lineWidth: 5, dash: [1.4, 1.8]))
                    .clipShape(Circle())
            } else {
                Circle().fill(tint)
            }
        }
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)
    }
}
