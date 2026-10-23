import Foundation
import Testing

/// LA5: regression guards for everything the system needs to mirror the iPhone Live Activity into the watch Smart Stack.
/// The Smart Stack layout lives in a WidgetKit extension that Core cannot import, so these tests read the project definition,
/// the Info.plists and the widget source from the repository checkout.
@Suite("LA5 Watch Smart Stack configuration")
struct LiveActivityWatchConfigTests {
    private static let root: URL = {
        // .../Packages/TimetrackCore/Tests/TimetrackCoreTests/<file> -> repository root
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }()

    private func text(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appendingPathComponent(path), encoding: .utf8)
    }

    private func plist(_ path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: Self.root.appendingPathComponent(path))
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test func liveActivityPlistsDeclareSupport() throws {
        #expect(try plist("Sources/WidgetIOS/Info.plist")["NSSupportsLiveActivities"] as? Bool == true)
        #expect(try plist("Sources/iOS/Info.plist")["NSSupportsLiveActivities"] as? Bool == true)
    }

    @Test func widgetDeclaresAndHandlesSmallFamily() throws {
        let source = try text("Sources/WidgetIOS/TimetrackWidgetIOS.swift")
        #expect(source.contains(".supplementalActivityFamilies([.small, .medium])"))
        #expect(source.contains("case .medium: LiveActivityBanner(state: state)"))
        #expect(source.contains("@unknown default"))
        #expect(source.contains("@Environment(\\.activityFamily)"))
        // The family switch must name .small explicitly (no wildcard sharing a branch with it), see Apple forum thread 776101.
        #expect(source.contains("case .small: LiveActivitySmall(state: state)"))
        #expect(!source.contains("case .small, _"))
    }

    @Test func familyLayoutsAreNeverEmpty() throws {
        let views = try text("Sources/WidgetShared/LiveActivityViews.swift")
        let small = try #require(views.range(of: "struct LiveActivitySmall: View"))
        let body = String(views[small.lowerBound...].prefix(2_500))
        #expect(!body.contains("EmptyView()"))
        #expect(body.contains("LiveWorkedClock"))
        // LA5: constructs of the unconfirmed LA3 layout must not come back without a device check.
        let code = body.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        #expect(!code.contains("ViewThatFits"))
        #expect(!code.contains("fixedSize"))
        #expect(!code.contains("dynamicTypeSize"))
    }

    @Test func watchAppIsCompanionOfTheiPhoneAppAndEmbedded() throws {
        let watch = try plist("Sources/Watch/Info.plist")
        #expect(watch["WKCompanionAppBundleIdentifier"] as? String == "de.linolaske.timetrack")
        #expect(watch["WKApplication"] as? Bool == true)
        let project = try text("project.yml")
        #expect(project.contains("- target: TimetrackWatch"))
        #expect(project.contains("PRODUCT_BUNDLE_IDENTIFIER: de.linolaske.timetrack.watchkitapp"))
    }

    @Test func activityAttributesAreRequestedWithoutPushAndWithStandardStyle() throws {
        let source = try text("Sources/WidgetShared/TimerLiveActivity.swift")
        // A transient style would not stay in the Smart Stack; the default (standard) must be kept.
        #expect(!source.contains("style: .transient"))
        #expect(source.contains("Activity.request("))
    }
}
