import Foundation
import Observation
import TimetrackCore

/// Fills the account's vacation request template for one vacation absence (AB1; PWA `VacationRequestDialog`): loads template, mapping,
/// balance, work models and holidays, lets the user confirm substitute and free days, generates the PDF with PDFKit and can attach
/// it to the absence. Template upload and mapping editing stay in the web app.
@MainActor
@Observable
public final class VacationRequestStore {
    public enum Phase: Equatable {
        case loading
        /// The server holds no template (`exists == false` or 404 on the file).
        case noTemplate
        case ready
        case failed(TimetrackError)
    }

    public struct Generated: Sendable, Equatable {
        /// X4: one id per generated PDF; the share file is refreshed for every new id (equal-sized PDFs differ in content).
        public let id: UUID
        public let data: Data
        public let fileName: String
        public let skippedFields: [String]
        public let filledCount: Int

        public init(id: UUID = UUID(), data: Data, fileName: String, skippedFields: [String], filledCount: Int) {
            self.id = id; self.data = data; self.fileName = fileName; self.skippedFields = skippedFields; self.filledCount = filledCount
        }
    }

    public enum AttachState: Equatable {
        case idle
        case saving
        case saved
        case failed(UploadFailure)
    }

    public private(set) var phase: Phase = .loading
    public private(set) var request: FormRequestData?
    /// Highest free-range position the template addresses (0: the template has no such field).
    public private(set) var freeRangeSlots = 0
    public private(set) var mappedFieldCount = 0
    public private(set) var generated: Generated?
    public private(set) var isGenerating = false
    /// Set when the PDF could not be produced; `nil` otherwise.
    public private(set) var generationProblem: FormPDFProblem?
    public private(set) var attachState: AttachState = .idle

    public var substitute = "" { didSet { if substitute != oldValue { invalidate() } } }
    public var freeConfirmed = true { didSet { if freeConfirmed != oldValue { invalidate() } } }
    public var flatten = false { didSet { if flatten != oldValue { invalidate() } } }

    public let absence: Absence
    private let client: APIClient
    private let today: LocalDay
    private let onAttached: (@MainActor () -> Void)?
    private var template: Data?
    private var mapping = FormMapping()

    public init(client: APIClient, absence: Absence, today: LocalDay, onAttached: (@MainActor () -> Void)? = nil) {
        self.client = client
        self.absence = absence
        self.today = today
        self.onAttached = onAttached
    }

    /// Free-day ranges that fit into the template and those that do not (the UI warns about the overflow).
    public var freeRangeFit: (shown: [FormDayRange], overflow: [FormDayRange]) {
        FormCalendar.fit(request?.freeRanges ?? [], slots: freeRangeSlots)
    }

    /// X4: counts input changes. A PDF whose generation started under an older value is discarded, never shown or attached.
    private var inputGeneration = 0

    private func invalidate() {
        inputGeneration += 1
        generated = nil
        generationProblem = nil
        attachState = .idle
    }

    public func load() async {
        phase = .loading
        do {
            let info = try await client.getVacationRequestForm()
            guard info.exists else { phase = .noTemplate; return }
            let file: Data
            do {
                file = try await client.downloadVacationRequestFormFile()
            } catch let error as TimetrackError where error.status == 404 {
                phase = .noTemplate
                return
            }
            let startYear = LocalDays.parse(absence.startDate)?.year ?? 0
            let endYear = LocalDays.parse(absence.endDate)?.year ?? startYear
            async let balanceResult = client.getVacationBalance(year: startYear)
            async let modelsResult = client.listWorkModels()
            var holidays: [CalendarDay] = []
            for year in startYear...max(endYear, startYear) { holidays += try await client.listHolidays(year: year) }
            let (balance, models) = try await (balanceResult, modelsResult)

            template = file
            mapping = FormMapping(json: info.mapping)
            flatten = mapping.flatten
            mappedFieldCount = mapping.fields.count + mapping.overlays.count
            freeRangeSlots = mapping.freeRangeSlots
            request = FormRequestData(FormRequestInputs(
                from: absence.startDate, to: absence.endDate, halfDayStart: absence.halfDayStart ?? false, halfDayEnd: absence.halfDayEnd ?? false,
                today: today, balance: balance, models: models, holidays: holidays,
                inBalance: absence.status != .cancelled && absence.status != .rejected))
            invalidate()
            phase = .ready
        } catch let error as TimetrackError {
            if error != .cancelled { phase = .failed(error) }
        } catch {
            phase = .failed(.cancelled)
        }
    }

    /// Fills the template. Heavy work runs off the main actor.
    public func generate() async {
        guard let template, var data = request, !isGenerating else { return }
        let generation = inputGeneration
        isGenerating = true
        generationProblem = nil
        attachState = .idle
        defer { isGenerating = false }
        data.substitute = substitute
        if !freeConfirmed { data.freeRanges = [] }
        let mapping = mapping, flatten = flatten, name = vacationRequestFileName(from: data.from, to: data.to), input = data
        #if canImport(PDFKit)
        let outcome: Result<FormFillResult, FormPDFProblem> = await Task.detached {
            do { return .success(try FormPDF.fill(template: template, mapping: mapping, request: input, flatten: flatten)) } catch let problem as FormPDFProblem { return .failure(problem) } catch { return .failure(.unreadable) }
        }.value
        // The inputs changed while the PDF was being filled: its content is stale.
        guard generation == inputGeneration else { return }
        switch outcome {
        case .success(let result): generated = Generated(data: result.data, fileName: name, skippedFields: result.skipped, filledCount: result.filledCount)
        case .failure(let problem): generationProblem = problem
        }
        #else
        generationProblem = .unreadable
        #endif
    }

    /// "Als Anhang speichern": uploads the generated PDF and links it to the absence.
    public func saveAsAttachment() async {
        guard let generated, attachState != .saving else { return }
        attachState = .saving
        let generation = inputGeneration
        do {
            try await client.uploadAttachment(absenceId: absence.id, name: generated.fileName, contentType: "application/pdf", data: generated.data)
            // The upload itself cannot be taken back; if the inputs changed meanwhile the state belongs to the new inputs.
            if generation == inputGeneration { attachState = .saved }
            onAttached?()
        } catch let error as TimetrackError {
            attachState = .failed(UploadFailure(error))
        } catch {
            attachState = .failed(.offline)
        }
    }
}
