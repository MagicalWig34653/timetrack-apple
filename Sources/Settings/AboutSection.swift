import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// "Über Timetrack": app version/build and, from `GET /system/info`, the backend version, revision and API version. Members see the
/// version fields only; administrators additionally database, migrations, uptime and replica. Old backends without the endpoint get a note.
struct AboutSection: View {
    @Environment(AppModel.self) private var model
    let build: AppBuildInfo
    @State private var copied = false

    var body: some View {
        FormSection("about.title", footer: "about.footer") {
            FormRow("about.app_version") { Text(verbatim: build.display).monospacedDigit().textSelection(.enabled).accessibilityIdentifier("about.app.version") }
            FormRow("settings.license") { Text(verbatim: "AGPL-3.0-only") }
            backendRows
            Button { copy() } label: {
                Label(copied ? "about.copied" : "about.copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(TT.textPrimary)
            .accessibilityIdentifier("about.copy")
        }
        .task { await model.refreshSystemInfo() }
    }

    @ViewBuilder private var backendRows: some View {
        switch model.systemInfo {
        case .idle, .loading:
            FormRow("about.backend") { Text("about.loading").foregroundStyle(TT.textSecondary) }
        case .unavailable:
            Text("about.unavailable").font(TTFont.meta).foregroundStyle(TT.textSecondary)
                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                .accessibilityIdentifier("about.unavailable")
        case .loaded(let info):
            let backend = info.backend
            FormRow("about.backend_version") { Text(verbatim: backend.version).monospacedDigit().textSelection(.enabled).accessibilityIdentifier("about.backend.version") }
            FormRow("about.revision") { Text(verbatim: backend.shortRevisionText ?? String(localized: "about.unknown")).font(.system(.body, design: .monospaced)).textSelection(.enabled).accessibilityIdentifier("about.backend.revision") }
            if let date = SystemInfo.shortDate(backend.buildDate) { FormRow("about.build_date") { Text(verbatim: date).monospacedDigit() } }
            FormRow("about.api_version") { Text(verbatim: backend.apiVersion).monospacedDigit().accessibilityIdentifier("about.backend.api") }
            if backend.hasOperationalDetails {
                if let database = backend.database { FormRow("about.database") { Text(verbatim: database) } }
                if let migrations = backend.schemaMigrations {
                    FormRow("about.migrations") {
                        Text(backend.migrationsPending == true ? "about.migrations_pending \(migrations)" : "about.migrations_value \(migrations)").monospacedDigit()
                    }
                }
                if let uptime = backend.uptimeSeconds { FormRow("about.uptime") { Text(verbatim: SystemInfo.formatUptime(uptime)) } }
                if let replica = backend.replicaId { FormRow("about.replica") { Text(verbatim: replica).font(.system(.body, design: .monospaced)).lineLimit(1).truncationMode(.middle) } }
            }
        }
    }

    private func copy() {
        let text = build.supportText(backend: model.systemInfo.info)
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        TTHaptics.play(.success)
        copied = true
        Task { try? await Task.sleep(for: .seconds(2)); copied = false }
    }
}
