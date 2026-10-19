import SwiftUI
import Testing
@testable import TimetrackDesign

@Suite struct SegmentedRingTests {
    @Test func arcsFollowEachOtherFromTwelveOClock() {
        let arcs = SegmentedRing<EmptyView>.arcs(for: [0.25, 0.125, 0.5])
        #expect(arcs.map(\.start) == [0, 0.25, 0.375])
        #expect(arcs.map(\.end) == [0.25, 0.375, 0.875])
    }

    @Test func sumIsCappedAtOneAndBadValuesAreSkipped() {
        let arcs = SegmentedRing<EmptyView>.arcs(for: [0.7, .nan, 0.6, -1])
        #expect(arcs[0].end == 0.7)
        #expect(arcs[1].start == arcs[1].end)
        #expect(abs(arcs[2].end - 1) < 1e-9)
        #expect(arcs[3].start == arcs[3].end)
    }
}
