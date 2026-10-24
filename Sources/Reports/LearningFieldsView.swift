import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// Learning-field list of the account: add, rename, number, reorder, delete. Entries keep their name snapshot, so renaming or
/// deleting never changes existing reports.
struct LearningFieldsView: View {
    @Bindable var store: ReportsStore
    @State private var editing: FieldRequest?
    @State private var deleting: LearningField?

    struct FieldRequest: Identifiable {
        let id = UUID()
        let field: LearningField?
    }

    var body: some View {
        List {
            if let error = store.error {
                ErrorBanner(message: error.germanDescription, retryTitle: "common.retry") { store.error = nil; Task { await store.loadLearningFields() } }
                    .listRowBackground(Color.clear)
            }
            Section {
                Text(verbatim: BH.s("fields.intro")).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                    .listRowBackground(Color.clear)
            }
            if store.learningFields.isEmpty {
                EmptyState(symbol: "list.number", title: LocalizedStringKey(BH.s("fields.empty_title")), message: LocalizedStringKey(BH.s("fields.empty_text")))
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(store.learningFields) { field in
                        Button { editing = FieldRequest(field: field) } label: {
                            HStack(spacing: TT.Space.m) {
                                if let number = field.number {
                                    Text(verbatim: "\(number)").font(TTFont.numeral).foregroundStyle(TT.textSecondary)
                                        .frame(minWidth: 28, alignment: .trailing)
                                }
                                Text(verbatim: field.name).font(TTFont.body).foregroundStyle(TT.textPrimary).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: 44).contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(Text(verbatim: field.number.map { BH.s("fields.spoken_number", $0, field.name) } ?? field.name))
                        .accessibilityHint(Text(verbatim: BH.s("fields.hint")))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("reports.field.row")
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { deleting = field } label: { Label(BH.s("fields.delete"), systemImage: "trash") }
                        }
                        .contextMenu {
                            Button { editing = FieldRequest(field: field) } label: { Label(BH.s("fields.edit"), systemImage: "pencil") }
                            Button(role: .destructive) { deleting = field } label: { Label(BH.s("fields.delete"), systemImage: "trash") }
                        }
                        .accessibilityAction(named: Text(verbatim: BH.s("fields.delete"))) { deleting = field }
                    }
                    .onMove { source, destination in Task { await store.moveLearningField(from: source, to: destination) } }
                } footer: { Text(verbatim: BH.s("fields.footer")) }
            }
        }
        .scrollContentBackground(.hidden)
        .ttScreenBackground()
        .navigationTitle(BH.s("fields.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(iOS)
            if store.learningFields.count > 1 { ToolbarItem(placement: .topBarLeading) { EditButton().accessibilityIdentifier("reports.fields.reorder") } }
            #endif
            ToolbarItem(placement: .primaryAction) {
                Button { editing = FieldRequest(field: nil) } label: { Label(BH.s("fields.add"), systemImage: "plus") }
                    .accessibilityIdentifier("reports.field.add")
            }
        }
        .task { await store.loadLearningFields() }
        .sheet(item: $editing) { request in LearningFieldSheet(store: store, field: request.field) }
        .confirmationDialog(deleting.map { BH.s("fields.delete_confirm", $0.name) } ?? "", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { field in
            Button(BH.s("fields.delete"), role: .destructive) { Task { await store.deleteLearningField(field) } }
        } message: { _ in Text(verbatim: BH.s("fields.delete_message")) }
    }
}

struct LearningFieldSheet: View {
    let store: ReportsStore
    let field: LearningField?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var numberText: String
    @State private var problem: ReportsStore.LearningFieldProblem?
    @SwiftUI.FocusState private var focused: Bool

    init(store: ReportsStore, field: LearningField?) {
        self.store = store
        self.field = field
        _name = State(initialValue: field?.name ?? "")
        _numberText = State(initialValue: field?.number.map(String.init) ?? "")
    }

    private var number: Int? { Int(numberText.trimmingCharacters(in: .whitespaces)) }
    private var numberInvalid: Bool { !numberText.trimmingCharacters(in: .whitespaces).isEmpty && number == nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TT.Space.l) {
                    if let error = store.error, error.knownCode == .learningFieldExists {
                        HintBanner(LocalizedStringKey(error.germanDescription), symbol: "exclamationmark.triangle.fill")
                    } else if let error = store.error {
                        ErrorBanner(message: error.germanDescription, retryTitle: "common.retry") { Task { await save() } }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: TT.Space.s) {
                            Text(verbatim: BH.s("fields.name")).font(TTFont.label).foregroundStyle(TT.textSecondary)
                            TextField(BH.s("fields.name_placeholder"), text: $name).focused($focused).textFieldStyle(.plain).ttField()
                                .submitLabel(.done).onSubmit { Task { await save() } }
                                .accessibilityIdentifier("reports.field.name")
                            if problem == .nameMissing { Label(BH.s("fields.name_missing"), systemImage: "exclamationmark.circle.fill").font(TTFont.meta).foregroundStyle(TT.danger) }
                            if problem == .nameTooLong { Label(BH.s("editor.field_too_long"), systemImage: "exclamationmark.circle.fill").font(TTFont.meta).foregroundStyle(TT.danger) }
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: TT.Space.s) {
                            Text(verbatim: BH.s("fields.number")).font(TTFont.label).foregroundStyle(TT.textSecondary)
                            TextField(BH.s("fields.number_placeholder"), text: $numberText).textFieldStyle(.plain).ttField()
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                                .accessibilityIdentifier("reports.field.number")
                            if numberInvalid { Label(BH.s("fields.number_invalid"), systemImage: "exclamationmark.circle.fill").font(TTFont.meta).foregroundStyle(TT.danger) }
                        }
                    }
                }
                .padding(TT.Space.l).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .ttScreenBackground()
            .navigationTitle(BH.s(field == nil ? "fields.add" : "fields.edit"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(BH.s("common.cancel")) { store.error = nil; dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(BH.s("common.save")) { Task { await save() } }.disabled(store.isBusy).accessibilityIdentifier("reports.field.save")
                }
            }
        }
        .task { store.error = nil; focused = true }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #else
        .presentationDetents([.medium])
        #endif
    }

    private func save() async {
        problem = ReportsStore.problem(name: name, number: number)
        guard problem == nil, !numberInvalid else { return }
        if await store.saveLearningField(name: name, number: number, editing: field) { dismiss() }
    }
}
