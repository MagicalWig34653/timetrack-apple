import SwiftUI
import QuartzCore

#if DEBUG
/// Z2: frame-time approximation for UI tests (`TT_DEV_FRAMEMETER=1`, Debug builds only). A display link records the interval between
/// frames; a long interval means the main thread (or the render server) missed frames. The overlay shows the numbers so a UI test can read
/// them as an accessibility value; tapping the overlay resets the counters. Simulator numbers compare builds with each other, they are no
/// substitute for a device measurement.
@MainActor
final class FrameMeter {
    static let shared = FrameMeter()
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private(set) var frames = 0
    private(set) var over20 = 0
    private(set) var over34 = 0
    private(set) var worst: CFTimeInterval = 0
    private(set) var busy: CFTimeInterval = 0

    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: Trampoline { [weak self] in self?.tick($0) }, selector: #selector(Trampoline.fire(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func reset() { frames = 0; over20 = 0; over34 = 0; worst = 0; busy = 0; last = 0 }

    private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        defer { last = now }
        guard last > 0 else { return }
        let delta = now - last
        guard delta < 0.5 else { return } // an idle gap (nothing to draw), not a slow frame
        frames += 1
        busy += delta
        worst = max(worst, delta)
        if delta > 0.020 { over20 += 1 }
        if delta > 0.034 { over34 += 1 }
    }

    var summary: String {
        "frames=\(frames) over20ms=\(over20) over34ms=\(over34) worstMs=\(Int(worst * 1000)) seconds=\(String(format: "%.1f", busy))"
    }

    private final class Trampoline: NSObject {
        let handler: (CADisplayLink) -> Void
        init(_ handler: @escaping (CADisplayLink) -> Void) { self.handler = handler }
        @objc func fire(_ link: CADisplayLink) { handler(link) }
    }
}

struct FrameMeterOverlay: ViewModifier {
    @State private var text = ""
    private let enabled = ProcessInfo.processInfo.environment["TT_DEV_FRAMEMETER"] != nil

    func body(content: Content) -> some View {
        if enabled {
            content
                .onAppear { FrameMeter.shared.start() }
                .overlay(alignment: .bottomLeading) {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(verbatim: FrameMeter.shared.summary).font(.system(size: 1)).foregroundStyle(.clear)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                            .onTapGesture { FrameMeter.shared.reset() }
                            .accessibilityElement(children: .ignore)
                            .accessibilityIdentifier("framemeter")
                            .accessibilityLabel(Text(verbatim: FrameMeter.shared.summary))
                    }
                }
        } else {
            content
        }
    }
}

extension View { func frameMeter() -> some View { modifier(FrameMeterOverlay()) } }
#else
extension View { func frameMeter() -> some View { self } }
#endif
