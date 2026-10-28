import Testing
@testable import TimetrackStores

@Suite("V5 week swipe")
struct WeekSwipeTests {
    @Test func leftIsNextRightIsPrevious() {
        #expect(WeekSwipe.shift(translationX: -100, translationY: 5) == 1)
        #expect(WeekSwipe.shift(translationX: 100, translationY: -5) == -1)
    }
    @Test func shortOrVerticalDragsDoNotSwitch() {
        #expect(WeekSwipe.shift(translationX: -40, translationY: 0) == nil)
        #expect(WeekSwipe.shift(translationX: -100, translationY: 90) == nil)
        #expect(WeekSwipe.shift(translationX: 10, translationY: 200) == nil)
    }
    @Test func fastFlickCountsEvenWhenShort() {
        #expect(WeekSwipe.shift(translationX: -40, translationY: 3, predictedEndX: -220) == 1)
        #expect(WeekSwipe.shift(translationX: -10, translationY: 0, predictedEndX: -300) == nil)
    }
    @Test func tracksOnlyHorizontalDrags() {
        #expect(WeekSwipe.tracks(translationX: 30, translationY: 4))
        #expect(!WeekSwipe.tracks(translationX: 30, translationY: 30))
        #expect(!WeekSwipe.tracks(translationX: 5, translationY: 0))
    }
}
