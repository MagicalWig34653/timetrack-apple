import Foundation
import Observation
import TimetrackCore

/// State of the "Urlaub" tab (module `planning`): vacation balance, absences of one calendar year, absence CRUD and vacation settings.
@MainActor
@Observable
public final class PlanningStore {
    public private(set) var year: Int
    public private(set) var balance: VacationBalance?
    public private(set) var absences: [Absence] = []
    public private(set) var settings: VacationSettings?
    public private(set) var entries = VacationEntries()
    public private(set) var isLoading = false
    /// Filter and sort of the absence list (V3); remembered in `defaults`.
    public var listOptions: AbsenceListOptions {
        didSet { if listOptions != oldValue { listOptions.save(to: defaults) } }
    }
    public var error: TimetrackError?
    /// Called after every successful absence change (the calendar reloads its month).
    public var onAbsencesChanged: (@MainActor () -> Void)?
    /// Reports the result of absence and settings writes (never loads).
    public var onOutcome: StoreOutcomeHandler?

    private let client: APIClient
    private let defaults: UserDefaults
    public let calendar: DayCalendar

    public init(client: APIClient, calendar: DayCalendar, now: Date = .now, defaults: UserDefaults = .standard) {
        self.client = client
        self.calendar = calendar
        self.defaults = defaults
        self.listOptions = AbsenceListOptions.load(from: defaults)
        self.year = LocalDays.parse(calendar.day(for: now))?.year ?? Calendar(identifier: .gregorian).component(.year, from: now)
    }

    public var today: LocalDay { calendar.day(for: .now) }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        let year = year
        do {
            async let balanceResult = client.getVacationBalance(year: year)
            async let absenceResult = client.listAbsences(from: LocalDays.format(year: year, month: 1, day: 1), to: LocalDays.format(year: year, month: 12, day: 31))
            let (loadedBalance, loadedAbsences) = try await (balanceResult, absenceResult)
            guard year == self.year else { return }
            balance = loadedBalance
            absences = loadedAbsences
                .filter { $0.status != .cancelled && $0.status != .rejected }
                .sorted { $0.startDate < $1.startDate }
            error = nil
        } catch let failure as TimetrackError {
            if failure != .cancelled { error = failure }
        } catch {
            self.error = .cancelled
        }
    }

    /// The absences after the selected filters and sort order.
    public var visibleAbsences: [Absence] { listOptions.apply(to: absences, today: today) }

    // MARK: - Attachments (contract v0.24.0)

    public func attachments(of absence: Absence) async throws -> [FileMeta] {
        try await client.listAbsenceAttachments(id: absence.id)
    }

    /// File content for the preview; uses `disposition=inline` for types the server can show inline.
    public func fileData(_ file: FileMeta) async throws -> Data {
        try await client.downloadFile(id: file.id, inline: file.supportsInline)
    }

    /// Store for the attachment sheet of one absence (AB1); reloads this list when attachments change so the paperclips stay right.
    public func makeAttachmentsStore(for absence: Absence) -> AbsenceAttachmentsStore {
        AbsenceAttachmentsStore(client: client, absenceId: absence.id) { [weak self] in Task { await self?.load() } }
    }

    /// Store for the vacation request form of one vacation absence (AB1).
    public func makeRequestStore(for absence: Absence) -> VacationRequestStore {
        VacationRequestStore(client: client, absence: absence, today: today) { [weak self] in Task { await self?.load() } }
    }

    public func shiftYears(_ count: Int) async {
        year += count
        balance = nil
        absences = []
        await load()
    }

    // MARK: - Absences

    /// Creates (`editing == nil`) or updates an absence with its version. Returns the stored absence; on failure `error` is set.
    @discardableResult
    public func saveAbsence(_ input: AbsenceInput, editing: Absence?) async -> Absence? {
        do {
            let stored: Absence
            if let editing {
                stored = try await client.updateAbsence(id: editing.id, input, ifMatchVersion: editing.version)
            } else {
                stored = try await client.createAbsence(input)
            }
            error = nil
            onOutcome?(.saved)
            await load()
            onAbsencesChanged?()
            return stored
        } catch {
            record(error)
            return nil
        }
    }

    @discardableResult
    public func deleteAbsence(_ absence: Absence) async -> Bool {
        do {
            try await client.deleteAbsence(id: absence.id)
            error = nil
            onOutcome?(.deleted)
            await load()
            onAbsencesChanged?()
            return true
        } catch {
            record(error)
            return false
        }
    }

    // MARK: - Settings and manual entries

    public func loadSettings() async {
        do {
            settings = try await client.getVacationSettings()
            entries = try await client.listVacationEntries(year: year)
            error = nil
        } catch { record(error, notify: false) }
    }

    @discardableResult
    public func saveSettings(_ new: VacationSettings) async -> Bool {
        do {
            settings = try await client.putVacationSettings(new)
            error = nil
            onOutcome?(.saved)
            await load()
            return true
        } catch {
            record(error)
            return false
        }
    }

    @discardableResult
    public func addSnapshot(date: LocalDay, remainingHalfDays: Int) async -> Bool {
        await mutateEntries { _ = try await self.client.createVacationSnapshot(date: date, remainingHalfDays: remainingHalfDays) }
    }

    @discardableResult
    public func addAdjustment(date: LocalDay, halfDays: Int, reason: String) async -> Bool {
        await mutateEntries { _ = try await self.client.createVacationAdjustment(date: date, halfDays: halfDays, reason: reason) }
    }

    @discardableResult
    public func deleteEntry(id: UUID) async -> Bool {
        await mutateEntries { try await self.client.deleteVacationEntry(id: id) }
    }

    private func mutateEntries(_ action: () async throws -> Void) async -> Bool {
        do {
            try await action()
            error = nil
            onOutcome?(.saved)
            entries = try await client.listVacationEntries(year: year)
            await load()
            return true
        } catch {
            record(error)
            return false
        }
    }

    /// `notify: false` for reads (a failed load shows the error banner, not a failure haptic).
    private func record(_ failure: Error, notify: Bool = true) {
        if let failure = failure as? TimetrackError {
            if failure != .cancelled {
                error = failure
                if notify { onOutcome?(.failed) }
            }
        } else {
            error = .cancelled
        }
    }
}
