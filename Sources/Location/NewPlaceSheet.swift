import MapKit
import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// Creates a place at the current location (or a tapped map position) with a radius preview. Saves to the server.
struct NewPlaceSheet: View {
    let store: AutomationStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var radius = 150.0
    @State private var mode = AutomationMode.suggest
    @State private var locating = false
    @State private var locationFailed = false
    @State private var camera = MapCameraPosition.automatic

    private var canSave: Bool { coordinate != nil && !name.trimmingCharacters(in: .whitespaces).isEmpty && !store.isBusy }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TT.Space.l) {
                    TextField("Name, z. B. Büro", text: $name)
                        .ttField()
                        .accessibilityIdentifier("automation.newplace.name")
                    MapReader { proxy in
                        Map(position: $camera) {
                            if let coordinate {
                                Marker(name.isEmpty ? "Ort" : name, coordinate: coordinate)
                                MapCircle(center: coordinate, radius: radius)
                                    .foregroundStyle(TT.kindWork.opacity(0.22))
                                    .stroke(TT.kindWork, lineWidth: 2)
                            }
                        }
                        .mapStyle(.standard)
                        .frame(height: 240)
                        .clipShape(.rect(cornerRadius: TT.Radius.card, style: .continuous))
                        .onTapGesture(coordinateSpace: .local) { point in
                            if let tapped = proxy.convert(point, from: .local) { setCoordinate(tapped) }
                        }
                        .accessibilityIdentifier("automation.newplace.map")
                    }
                    Button { Task { await useCurrentLocation() } } label: {
                        Label(locating ? "Standort wird ermittelt…" : "Aktuellen Standort verwenden", systemImage: "location.fill")
                    }
                    .buttonStyle(.ttSecondary)
                    .disabled(locating)
                    .accessibilityIdentifier("automation.newplace.locate")
                    if locationFailed {
                        HintBanner("Der Standort konnte nicht ermittelt werden. Tippe stattdessen auf die Karte.", symbol: "exclamationmark.triangle.fill")
                    }
                    VStack(alignment: .leading, spacing: TT.Space.xs) {
                        HStack { Text("Radius"); Spacer(); Text("\(Int(radius)) m").monospacedDigit().foregroundStyle(TT.textSecondary) }
                        Slider(value: $radius, in: 100...500, step: 25).accessibilityIdentifier("automation.newplace.radius")
                        Text("Mindestens 100 m: kleinere Radien erkennt iOS nicht zuverlässig.").font(TTFont.meta).foregroundStyle(TT.textSecondary)
                    }
                    Picker("Automatik", selection: $mode) {
                        Text("Aus").tag(AutomationMode.off)
                        Text("Vorschlag").tag(AutomationMode.suggest)
                        Text("Direkt").tag(AutomationMode.direct)
                    }
                    .pickerStyle(.segmented)
                    if let error = store.error { ErrorBanner(message: error.germanDescription, retryTitle: "common.retry") { store.error = nil } }
                }
                .padding(TT.Space.l)
            }
            .ttScreenBackground()
            .navigationTitle("Neuer Ort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        guard let coordinate else { return }
                        let point = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
                        Task {
                            await store.createPlace(name: name.trimmingCharacters(in: .whitespaces), coordinate: point, radius: Int(radius), mode: mode)
                            if store.error == nil { dismiss() }
                        }
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("automation.newplace.save")
                }
            }
        }
        .presentationDetents([.large])
    }

    private func setCoordinate(_ value: CLLocationCoordinate2D) {
        coordinate = value
        camera = .region(MKCoordinateRegion(center: value, latitudinalMeters: max(radius * 6, 800), longitudinalMeters: max(radius * 6, 800)))
    }

    private func useCurrentLocation() async {
        locating = true
        locationFailed = false
        defer { locating = false }
        let service = AutomationRuntime.shared.service
        if service.status.permission == .notDetermined {
            service.requestWhenInUse()
            try? await Task.sleep(for: .seconds(1))
            // The permission dialog covers the sheet; wait until the user answered.
            for _ in 0..<60 where service.status.permission == .notDetermined { try? await Task.sleep(for: .milliseconds(500)) }
        }
        if let fix = await service.currentFix() {
            setCoordinate(CLLocationCoordinate2D(latitude: fix.latitude, longitude: fix.longitude))
        } else {
            locationFailed = true
        }
    }
}
