import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

// PL1: plan shares. Outgoing shares (who sees which part of my plan) and incoming shares (what others share with me, read only).
// Mirrors the PWA pages "Einstellungen > Freigaben" and "Geteilt mit mir". Everything is private unless a scope is switched on.

private extension ShareScopes.Scope {
    var titleKey: String { "share.scope." + rawValue }
    var textKey: String { "share.scope_text." + rawValue }
}

struct SharingScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let client = model.apiClient {
                SharingView(store: WeekStoreCache.shared.sharingStore(client, calendar: model.dayCalendar, ownHandle: model.account?.handle))
            }
        }
        .navigationTitle(PA.s("share.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

struct SharingView: View {
    @Bindable var store: SharingStore
    @State private var handle = ""
    @State private var newScopes = ShareScopes()
    @State private var revoking: Share?
    @State private var created = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.l) {
                if let error = store.error { ErrorBanner(message: error.germanDescription, retryTitle: "common.retry") { store.error = nil; Task { await store.load() } } }
                neverShared
                if store.isUnavailable {
                    Text(verbatim: PA.s("share.unavailable")).font(TTFont.body).foregroundStyle(TT.textSecondary)
                } else {
                    outgoing
                    newShare
                    incoming
                }
            }
            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .ttScreenBackground()
        .task { await store.load() }
        .refreshable { await store.load() }
        .confirmationDialog(revoking.map { PA.s("share.revoke_confirm", $0.recipientHandle) } ?? "", isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }), titleVisibility: .visible, presenting: revoking) { share in
            Button(PA.s("share.revoke"), role: .destructive) { Task { await store.revoke(share) } }
        } message: { _ in Text(verbatim: PA.s("share.revoke_message")) }
        .navigationDestination(item: Binding(get: { store.selected }, set: { if $0 == nil { store.closeSelection() } })) { share in
            SharedViewScreen(store: store, share: share)
        }
    }

    private var neverShared: some View {
        Card {
            VStack(alignment: .leading, spacing: TT.Space.xs) {
                Text(verbatim: PA.s("share.never_title")).font(TTFont.body.weight(.semibold)).foregroundStyle(TT.textPrimary)
                Text(verbatim: PA.s("share.never_text")).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                Text(verbatim: PA.s("share.never_outgoing")).font(TTFont.meta).foregroundStyle(TT.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Outgoing

    private var outgoing: some View {
        VStack(alignment: .leading, spacing: TT.Space.s) {
            Text(verbatim: PA.s("share.out_title")).font(TTFont.label).foregroundStyle(TT.textSecondary)
            if store.outgoing.isEmpty {
                Text(verbatim: PA.s("share.out_empty")).font(TTFont.body).foregroundStyle(TT.textSecondary).accessibilityIdentifier("share.out.empty")
            }
            ForEach(store.outgoing) { share in
                Card {
                    VStack(alignment: .leading, spacing: TT.Space.s) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: share.recipientHandle).font(TTFont.cardTitle).foregroundStyle(TT.textPrimary)
                                Text(verbatim: PA.s("share.since", share.createdAt.formatted(.dateTime.day().month().year().locale(Locale(identifier: "de_DE")))))
                                    .font(TTFont.meta).foregroundStyle(TT.textSecondary)
                            }
                            Spacer(minLength: 0)
                            Button(PA.s("share.revoke"), role: .destructive) { revoking = share }
                                .buttonStyle(.ttSecondary).fixedSize().accessibilityIdentifier("share.revoke.\(share.recipientHandle)")
                        }
                        ForEach(ShareScopes.Scope.allCases, id: \.self) { scope in
                            Toggle(isOn: Binding(get: { share.scopes[scope] }, set: { value in Task { await store.setScope(scope, to: value, of: share) } })) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: PA.s(scope.titleKey)).font(TTFont.body).foregroundStyle(TT.textPrimary)
                                    Text(verbatim: PA.s(scope.textKey)).font(TTFont.meta).foregroundStyle(TT.textSecondary).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .disabled(store.isBusy)
                            .accessibilityIdentifier("share.\(share.recipientHandle).\(scope.rawValue)")
                        }
                    }
                }
            }
        }
    }

    // MARK: New share

    private var problemText: String? {
        switch store.formProblem {
        case .handleMissing: PA.s("share.error.handle")
        case .toSelf: PA.s("share.error.self")
        case .noScope: PA.s("share.error.scope")
        case nil: nil
        }
    }

    private var newShare: some View {
        VStack(alignment: .leading, spacing: TT.Space.s) {
            Text(verbatim: PA.s("share.new_title")).font(TTFont.label).foregroundStyle(TT.textSecondary)
            Card {
                VStack(alignment: .leading, spacing: TT.Space.s) {
                    TextField(PA.s("share.recipient"), text: $handle)
                        .textFieldStyle(.roundedBorder).autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .accessibilityIdentifier("share.handle")
                    Text(verbatim: PA.s("share.recipient_hint")).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                    Text(verbatim: PA.s("share.scopes")).font(TTFont.body.weight(.semibold)).foregroundStyle(TT.textPrimary)
                    ForEach(ShareScopes.Scope.allCases, id: \.self) { scope in
                        Toggle(PA.s(scope.titleKey), isOn: Binding(get: { newScopes[scope] }, set: { newScopes[scope] = $0 }))
                            .accessibilityIdentifier("share.new.\(scope.rawValue)")
                    }
                    if let problemText { Text(verbatim: problemText).font(TTFont.meta).foregroundStyle(TT.danger).accessibilityIdentifier("share.problem") }
                    if created { Text(verbatim: PA.s("share.created")).font(TTFont.meta).foregroundStyle(TT.success) }
                    Button { Task { created = false; if await store.create(handle: handle, scopes: newScopes) { handle = ""; newScopes = ShareScopes(); created = true } } } label: {
                        Text(verbatim: PA.s("share.create")).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.ttPrimary).disabled(store.isBusy).accessibilityIdentifier("share.create")
                }
            }
        }
    }

    // MARK: Incoming

    private var incoming: some View {
        VStack(alignment: .leading, spacing: TT.Space.s) {
            Text(verbatim: PA.s("share.in_title")).font(TTFont.label).foregroundStyle(TT.textSecondary)
            if store.viewGone { Text(verbatim: PA.s("share.view.gone")).font(TTFont.meta).foregroundStyle(TT.warning) }
            if store.incoming.isEmpty {
                Text(verbatim: PA.s("share.in_empty")).font(TTFont.body).foregroundStyle(TT.textSecondary).accessibilityIdentifier("share.in.empty")
            } else {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(store.incoming.enumerated()), id: \.element.id) { index, share in
                            if index > 0 { Divider().padding(.leading, TT.Space.l) }
                            Button { Task { await store.select(share) } } label: {
                                HStack(spacing: TT.Space.m) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(verbatim: share.ownerDisplayName).font(TTFont.body).foregroundStyle(TT.textPrimary)
                                        HStack(spacing: TT.Space.xs) {
                                            ForEach(share.scopes.enabled, id: \.self) { StatusChip(verbatim: PA.s($0.titleKey)) }
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(TT.textTertiary).accessibilityHidden(true)
                                }
                                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m).contentShape(.rect)
                            }
                            .buttonStyle(.plain).accessibilityIdentifier("share.in.\(share.ownerDisplayName)")
                        }
                    }
                }
                Text(verbatim: PA.s("share.in_text")).font(TTFont.meta).foregroundStyle(TT.textSecondary)
            }
        }
    }
}

/// What the server releases for one incoming share in a date range: plan days, evaluated times, vacation periods.
struct SharedViewScreen: View {
    @Bindable var store: SharingStore
    let share: IncomingShare

    private var calendar: DayCalendar { store.calendar }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.l) {
                Text(verbatim: PA.s("share.in_text")).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                Card {
                    VStack(alignment: .leading, spacing: TT.Space.s) {
                        DatePicker(PA.s("share.view.from"), selection: dayBinding($store.from, calendar: calendar), displayedComponents: .date)
                        DatePicker(PA.s("share.view.to"), selection: dayBinding($store.to, calendar: calendar), displayedComponents: .date)
                        if store.rangeInvalid { Text(verbatim: PA.s("share.view.range_invalid")).font(TTFont.meta).foregroundStyle(TT.danger) }
                        Button { Task { await store.loadView() } } label: { Text(verbatim: PA.s("share.view.load")).frame(maxWidth: .infinity) }
                            .buttonStyle(.ttPrimary).disabled(store.viewIsLoading).accessibilityIdentifier("shared.load")
                    }
                }
                if let error = store.viewError { ErrorBanner(message: error.germanDescription, retryTitle: "common.retry") { Task { await store.loadView() } } }
                if store.viewIsLoading && store.view == nil { SkeletonList(rows: 3) }
                if let view = store.view { content(view) }
            }
            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .ttScreenBackground()
        .navigationTitle(PA.s("share.view.title", share.ownerDisplayName))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder private func content(_ view: SharedView) -> some View {
        if view.isEmpty {
            Text(verbatim: PA.s("share.view.nothing")).font(TTFont.body).foregroundStyle(TT.textSecondary)
        }
        if let plan = view.plan {
            section("share.scope.plan", empty: plan.isEmpty) {
                ForEach(plan) { day in
                    VStack(alignment: .leading, spacing: TT.Space.xs) {
                        HStack {
                            Text(verbatim: dayTitle(day.date, calendar: calendar)).font(TTFont.body).foregroundStyle(TT.textPrimary)
                            Spacer(minLength: 0)
                            if let blocks = day.blocks, !blocks.isEmpty {
                                // P13: blocks carry start, end and kind only; the server never releases places or notes.
                            } else if let start = day.plannedStart, let end = day.plannedEnd {
                                Text(verbatim: "\(start)–\(end)").font(TTFont.meta).foregroundStyle(TT.textSecondary).monospacedDigit()
                            }
                            Label(day.mode.plainName, systemImage: day.mode.symbol).font(TTFont.meta).foregroundStyle(day.mode.tint)
                        }
                        if let blocks = day.blocks, !blocks.isEmpty {
                            PlanTimeline(shared: blocks, height: 18, showsAxis: false)
                            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                                HStack(spacing: 6) {
                                    PlanKindSwatch(kind: block.kind, size: 16)
                                    Text(verbatim: "\(block.start)–\(block.end) \(block.kind.title)").font(TTFont.meta).foregroundStyle(TT.textSecondary).monospacedDigit()
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("share.plan.\(day.date)")
                }
            }
        }
        if let actual = view.actual {
            section("share.scope.actual", empty: actual.isEmpty) {
                ForEach(actual) { day in
                    HStack {
                        Text(verbatim: dayTitle(day.date, calendar: calendar)).font(TTFont.body).foregroundStyle(TT.textPrimary)
                        Spacer(minLength: 0)
                        Text(verbatim: timeRange(day)).font(TTFont.meta).foregroundStyle(TT.textSecondary).monospacedDigit()
                        Text(verbatim: DurationFormat.hoursMinutes(day.evaluatedWorkSeconds)).font(TTFont.meta).foregroundStyle(TT.textPrimary).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        if let vacation = view.vacation {
            section("share.scope.vacation", empty: vacation.isEmpty) {
                ForEach(vacation) { period in
                    Text(verbatim: period.startDate == period.endDate ? dayTitle(period.startDate, calendar: calendar)
                         : weekRangeText(start: period.startDate, end: period.endDate, calendar: calendar))
                        .font(TTFont.body).foregroundStyle(TT.textPrimary)
                }
            }
        }
    }

    private func timeRange(_ day: SharedView.ActualDay) -> String {
        guard let start = day.evaluatedStart, let end = day.evaluatedEnd else { return PA.s("share.view.no_times") }
        let style = Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "de_DE"), calendar: .current, timeZone: calendar.timeZone)
        return "\(start.formatted(style))–\(end.formatted(style))"
    }

    private func section<Rows: View>(_ title: String, empty: Bool, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: TT.Space.s) {
            Text(verbatim: PA.s(title)).font(TTFont.label).foregroundStyle(TT.textSecondary)
            Card {
                if empty {
                    Text(verbatim: PA.s("share.view.none_in_range")).font(TTFont.body).foregroundStyle(TT.textSecondary)
                } else {
                    VStack(alignment: .leading, spacing: TT.Space.s) { rows() }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
