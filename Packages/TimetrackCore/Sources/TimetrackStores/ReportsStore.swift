import Foundation
import Observation
import TimetrackCore

/// State of the Berichtsheft (BH1, module `reports`, ADR-0008): one ISO week with its entries, the learning-field list and the
/// week's sources (notes and files). Nothing is filled in automatically; the tracked work time of the week is only a hint.
/// Writes update the loaded week in place (sums are recomputed locally), so the list never waits for a second round trip.
@MainActor
@Observable
public final class ReportsStore {
    public private(set) var week: ReportWeekRef
    public private(set) var data: ReportWeek?
    public private(set) var learningFields: [LearningField] = []
    public private(set) var sources: [ReportSource] = []
    public private(set) var isLoading = false
    public private(set) var isBusy = false
    /// The server does not know the Berichtsheft (older version or module off): the screen shows a hint instead of an error.
    public private(set) var isUnavailable = false
    public private(set) var fieldsLoaded = false
    public var error: TimetrackError?

    public var onOutcome: StoreOutcomeHandler?
    private let client: APIClient
    public let calendar: DayCalendar
    private var generation = 0

    private let clock: @Sendable () -> Date

    /// `now` fixes the clock (tests); by default the real time is used.
    public init(client: APIClient, calendar: DayCalendar, now: Date? = nil) {
        self.client = client
        self.calendar = calendar
        if let now { self.clock = { now } } else { self.clock = { Date() } }
        self.week = ReportWeekRef(containing: calendar.day(for: clock())) ?? ReportWeekRef(year: 2026, week: 1)
    }

    public var today: LocalDay { calendar.day(for: clock()) }
    public var currentWeek: ReportWeekRef { ReportWeekRef(containing: today) ?? week }
    public var isCurrentWeek: Bool { week == currentWeek }
    public var status: ReportStatus { data?.status ?? .draft }
    public var entries: [ReportEntry] { data?.entries ?? [] }

    // MARK: Loading and navigation

    /// Loads the selected week, its sources and (once) the learning fields. A newer call makes an older one obsolete.
    public func load() async {
        generation += 1
        let mine = generation
        let ref = week
        isLoading = true
        defer { if mine == generation { isLoading = false } }
        do {
            async let loadedWeek = client.getReportWeek(ref)
            async let loadedSources = client.listReportSources(ref)
            async let loadedFields = client.listLearningFields()
            let (weekResult, sourceResult, fieldResult) = try await (loadedWeek, loadedSources, loadedFields)
            guard mine == generation else { return }
            data = weekResult
            sources = sourceResult
            learningFields = Self.ordered(fieldResult)
            fieldsLoaded = true
            error = nil
            isUnavailable = false
        } catch let failure as TimetrackError {
            guard mine == generation, failure != .cancelled else { return }
            if failure.status == 404, failure.knownCode != .moduleDisabled {
                isUnavailable = true
                data = nil
            } else {
                error = failure
            }
        } catch {
            return
        }
    }

    public func shiftWeeks(_ count: Int) async { await go(to: week.shifted(by: count)) }

    public func goToCurrentWeek() async { await go(to: currentWeek) }

    /// Opens a week; keeps the old content on screen only if it is the same week (a reload).
    public func go(to ref: ReportWeekRef) async {
        if ref != week {
            week = ref
            data = nil
            sources = []
        }
        error = nil
        await load()
    }

    /// Opens the week that contains `day`.
    public func go(toDay day: LocalDay) async {
        guard let ref = ReportWeekRef(containing: day) else { return }
        await go(to: ref)
    }

    /// Points the store at a week without loading it (the screen's `.task` loads); used by links from other screens.
    public func select(week ref: ReportWeekRef) {
        guard ref != week else { return }
        week = ref
        data = nil
        sources = []
    }

    // MARK: Status

    public func setStatus(_ status: ReportStatus) async {
        guard !isBusy, status != self.status else { return }
        isBusy = true
        defer { isBusy = false }
        let ref = week
        do {
            let updated = try await client.putReportWeekStatus(ref, status: status)
            if ref == week { data = updated }
            error = nil
            onOutcome?(.saved)
        } catch {
            fail(error)
        }
    }

    // MARK: Entries

    /// Creates (`entry == nil`) or updates an entry and merges the answer into the loaded week. Throws the API error to the caller
    /// (the editor decides what a conflict means); the store only reports user-visible success.
    @discardableResult
    public func save(_ input: ReportEntryInput, replacing entry: ReportEntry?) async throws -> ReportEntry {
        let stored: ReportEntry
        if let entry {
            stored = try await client.updateReportEntry(id: entry.id, input, ifMatchVersion: entry.version)
        } else {
            stored = try await client.createReportEntry(input)
        }
        merge(stored)
        return stored
    }

    @discardableResult
    public func delete(_ entry: ReportEntry) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            try await client.deleteReportEntry(id: entry.id)
            removeLocally(entry.id)
            error = nil
            onOutcome?(.saved)
            return true
        } catch let failure as TimetrackError where failure.status == 404 {
            removeLocally(entry.id) // gone elsewhere already: the list was stale
            return true
        } catch {
            fail(error)
            return false
        }
    }

    /// Reads the current server version of one entry from the week it belongs to (conflict resolution).
    public func serverVersion(of id: UUID, on day: LocalDay) async -> ReportEntry? {
        guard let ref = ReportWeekRef(containing: day), let fresh = try? await client.getReportWeek(ref) else { return nil }
        if ref == week { data = fresh }
        return fresh.entries.first { $0.id == id }
    }

    func merge(_ entry: ReportEntry) {
        guard var current = data, entry.date >= current.startDate, entry.date <= current.endDate else {
            // The entry moved to another week: it leaves this one.
            removeLocally(entry.id)
            return
        }
        if let index = current.entries.firstIndex(where: { $0.id == entry.id }) {
            current.entries[index] = entry
        } else {
            current.entries.append(entry)
        }
        current.entries.sort { ($0.date, $0.createdAt ?? .distantPast) < ($1.date, $1.createdAt ?? .distantPast) }
        data = Self.recomputed(current)
    }

    private func removeLocally(_ id: UUID) {
        guard var current = data else { return }
        current.entries.removeAll { $0.id == id }
        data = Self.recomputed(current)
    }

    /// Sums per week and per learning field from the entries (same grouping as the server: by name snapshot, first appearance first).
    static func recomputed(_ week: ReportWeek) -> ReportWeek {
        var result = week
        result.totalSeconds = week.entries.reduce(0) { $0 + $1.durationSeconds }
        var order: [String] = []
        var totals: [String: Int] = [:]
        for entry in week.entries {
            if totals[entry.learningField] == nil { order.append(entry.learningField) }
            totals[entry.learningField, default: 0] += entry.durationSeconds
        }
        result.byLearningField = order.map { ReportFieldTotal(learningField: $0, seconds: totals[$0] ?? 0) }
        return result
    }

    // MARK: Learning fields

    static func ordered(_ fields: [LearningField]) -> [LearningField] {
        fields.sorted { ($0.sortOrder, $0.number ?? Int.max, $0.name.lowercased()) < ($1.sortOrder, $1.number ?? Int.max, $1.name.lowercased()) }
    }

    /// Reloads the list only (after the learning-field screen or when the editor opens without a loaded week).
    public func loadLearningFields() async {
        do {
            learningFields = Self.ordered(try await client.listLearningFields())
            fieldsLoaded = true
            isUnavailable = false
        } catch let failure as TimetrackError {
            guard failure != .cancelled else { return }
            if failure.status == 404, failure.knownCode != .moduleDisabled { isUnavailable = true } else { error = failure }
        } catch {
            return
        }
    }

    /// Local checks of a learning-field form; nil = fine. The server enforces the same limits.
    public static func problem(name: String, number: Int?) -> LearningFieldProblem? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .nameMissing }
        if trimmed.count > 120 { return .nameTooLong }
        if let number, number < 0 { return .numberInvalid }
        return nil
    }

    public enum LearningFieldProblem: Sendable, Equatable { case nameMissing, nameTooLong, numberInvalid }

    /// Creates (`editing == nil`) or changes a learning field; returns whether it worked. A duplicate name sets `error` (409).
    @discardableResult
    public func saveLearningField(name: String, number: Int?, editing: LearningField?) async -> Bool {
        guard Self.problem(name: name, number: number) == nil, !isBusy else { return false }
        isBusy = true
        defer { isBusy = false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if let editing {
                let updated = try await client.updateLearningField(id: editing.id, LearningFieldInput(number: number, name: trimmed, sortOrder: editing.sortOrder))
                if let index = learningFields.firstIndex(where: { $0.id == editing.id }) { learningFields[index] = updated }
            } else {
                let next = (learningFields.map(\.sortOrder).max() ?? -1) + 1
                learningFields.append(try await client.createLearningField(LearningFieldInput(number: number, name: trimmed, sortOrder: next)))
            }
            learningFields = Self.ordered(learningFields)
            error = nil
            onOutcome?(.saved)
            return true
        } catch {
            fail(error)
            return false
        }
    }

    @discardableResult
    public func deleteLearningField(_ field: LearningField) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            try await client.deleteLearningField(id: field.id)
            learningFields.removeAll { $0.id == field.id }
            error = nil
            onOutcome?(.saved)
            return true
        } catch let failure as TimetrackError where failure.status == 404 {
            learningFields.removeAll { $0.id == field.id }
            return true
        } catch {
            fail(error)
            return false
        }
    }

    /// Moves one field in the list and stores the new order (sortOrder = position).
    public func moveLearningField(from source: IndexSet, to destination: Int) async {
        // Same result as SwiftUI's `move(fromOffsets:toOffset:)`, which is not available in the SwiftUI-free core.
        var moved = learningFields
        let taken = source.sorted().compactMap { moved.indices.contains($0) ? moved[$0] : nil }
        let before = source.filter { $0 < destination }.count
        for index in source.sorted().reversed() where moved.indices.contains(index) { moved.remove(at: index) }
        moved.insert(contentsOf: taken, at: max(0, min(moved.count, destination - before)))
        let previous = learningFields
        learningFields = moved
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            for (index, field) in moved.enumerated() where field.sortOrder != index {
                let stored = try await client.updateLearningField(id: field.id, LearningFieldInput(number: field.number, name: field.name, sortOrder: index))
                if let position = learningFields.firstIndex(where: { $0.id == field.id }) { learningFields[position] = stored }
            }
            onOutcome?(.saved)
        } catch {
            learningFields = previous
            fail(error)
        }
    }

    // MARK: Sources

    @discardableResult
    public func addNoteSource(_ text: String, day: LocalDay?) async -> Bool {
        let note = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty, note.count <= 4000, !isBusy else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            let created = try await client.createReportSource(ReportSourceInput(year: week.year, week: week.week, date: day, note: note))
            sources.append(created)
            bumpSourceCount()
            error = nil
            onOutcome?(.saved)
            return true
        } catch {
            fail(error)
            return false
        }
    }

    /// Uploads a file and attaches it to the week (or one day of it).
    @discardableResult
    public func addFileSource(name: String, contentType: String, data fileData: Data, day: LocalDay?) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            let meta = try await client.uploadFile(name: name, contentType: contentType, data: fileData)
            let created = try await client.createReportSource(ReportSourceInput(year: week.year, week: week.week, date: day, fileId: meta.id))
            sources.append(created)
            bumpSourceCount()
            error = nil
            onOutcome?(.saved)
            return true
        } catch {
            fail(error)
            return false
        }
    }

    @discardableResult
    public func removeSource(_ source: ReportSource) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            try await client.deleteReportSource(id: source.id)
            drop(source)
            error = nil
            onOutcome?(.saved)
            return true
        } catch let failure as TimetrackError where failure.status == 404 {
            drop(source)
            return true
        } catch {
            fail(error)
            return false
        }
    }

    private func drop(_ source: ReportSource) {
        sources.removeAll { $0.id == source.id }
        data?.sourceCount = sources.count
    }

    private func bumpSourceCount() { data?.sourceCount = sources.count }

    /// File content for the preview (same inline rule as absence attachments).
    public func fileData(_ file: FileMeta) async throws -> Data {
        try await client.downloadFile(id: file.id, inline: file.supportsInline)
    }

    // MARK: Copy for the IHK portal

    public struct CopyPayload: Sendable, Equatable {
        public let plain: String
        public let html: String
        public let isEmpty: Bool
    }

    /// Plain text from the server (the canonical format), rich text built from the loaded entries. If the server cannot be reached
    /// the plain text is built locally in the same format, so copying also works with a flaky connection.
    public func copyPayload() async -> CopyPayload {
        let ref = week
        let current = entries
        let html = ReportText.html(week: ref, entries: current)
        let plain: String
        if let served = try? await client.getReportWeekText(ref), !served.isEmpty {
            plain = served
        } else {
            plain = ReportText.plain(week: ref, entries: current)
        }
        return CopyPayload(plain: plain, html: html, isEmpty: current.isEmpty)
    }

    private func fail(_ error: Error) {
        guard let failure = error as? TimetrackError, failure != .cancelled else { return }
        self.error = failure
        onOutcome?(.failed)
    }
}
