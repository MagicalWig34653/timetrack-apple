import Foundation
import TimetrackCore

/// Zoom level of the one "Zeit" screen (Z2).
public enum TimeZoom: String, Sendable, Hashable, CaseIterable {
    case month, week
}

/// What the "Zeit" screen currently looks at: one anchor day, the zoom level and the planning mode of the week.
/// Month and week are two zoom levels of the same anchor; the week planner is an editing mode of the week, not another screen.
public struct TimeFocus: Equatable, Sendable {
    public var zoom: TimeZoom
    public private(set) var day: LocalDay
    /// Editing mode of the week zoom (rough plan per day). Always off in the month zoom.
    public var isPlanning: Bool {
        didSet { if zoom == .month { isPlanning = false } }
    }

    public init(zoom: TimeZoom = .week, day: LocalDay, isPlanning: Bool = false) {
        self.zoom = zoom
        self.day = day
        self.isPlanning = zoom == .week && isPlanning
    }

    public var monthKey: MonthKey { MonthKey(day: day) ?? MonthKey(year: 2026, month: 1) }
    public var weekStart: LocalDay { LocalDays.mondayOfWeek(containing: day) ?? day }
    public var weekEnd: LocalDay { LocalDays.adding(6, to: weekStart) ?? weekStart }

    /// Switching the zoom keeps the anchor day: the week that contains it, or the month that contains it.
    public mutating func setZoom(_ newZoom: TimeZoom) {
        zoom = newZoom
        if newZoom == .month { isPlanning = false }
    }

    /// Select a day (month grid tap, "Heute"). Does not change the zoom.
    public mutating func select(_ newDay: LocalDay) { day = newDay }

    /// Pages by whole weeks; the anchor keeps its weekday.
    public mutating func shiftWeeks(_ count: Int) {
        day = LocalDays.adding(7 * count, to: day) ?? day
    }

    /// Pages to another month. The anchor becomes `preferred` when it lies inside that month, otherwise the 1st
    /// (like the old calendar: today when visible, otherwise the first of the month).
    public mutating func move(toMonth key: MonthKey, preferring preferred: LocalDay) {
        if MonthKey(day: preferred) == key { day = preferred } else { day = key.firstDay }
    }

    public mutating func shiftMonths(_ count: Int, today: LocalDay) {
        move(toMonth: monthKey.adding(count), preferring: today)
    }

    public mutating func goToToday(_ today: LocalDay) { day = today }
}
