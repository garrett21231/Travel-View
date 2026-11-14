import SwiftUI
import TravelCore

/// Captures one complete snapshot for sharing, independently of the readable-text options.
struct ShareTripFileView: View {
    let store: TripStore
    let tripID: String
    @State private var package: SharedTripPackage?
    @State private var document: TripFileDocument?
    @State private var exporting = false
    @State private var sharingText = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let package, let document {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("A complete trip copy").font(.headline)
                            Text("This file includes all saved details, including notes, booking references, budget, checklist and flight lookup snapshots. The recipient can import it into Travel View and edit their own copy.")
                                .font(.subheadline).foregroundStyle(TravelTheme.secondary)
                            Text("Send it with AirDrop, Messages or Mail. You don’t need to save a file first, and no Travel View account is required.")
                                .font(.subheadline).foregroundStyle(TravelTheme.secondary)
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 12) { actions(document, title: package.trip.name) }
                                VStack(alignment: .leading, spacing: 12) { actions(document, title: package.trip.name) }
                            }
                        }.tripPanel()
                        receivingHelp
                        VStack(alignment: .leading, spacing: 14) {
                            Text("For someone without Travel View").font(.headline)
                            Text("Share a readable itinerary with optional notes, booking references and checklist.")
                                .font(.subheadline).foregroundStyle(TravelTheme.secondary)
                            Button("Share readable itinerary", systemImage: "doc.plaintext") { sharingText = true }
                                .buttonStyle(.bordered).accessibilityIdentifier("preview-itinerary-share")
                        }.tripPanel()
                        SharedTripPreview(package: package)
                    } else if let error {
                        ContentUnavailableView {
                            Label("Couldn’t prepare trip file", systemImage: "exclamationmark.triangle")
                        } description: { Text(error) } actions: { Button("Try again", action: prepare) }
                    } else { ProgressView("Preparing trip file…") }
                }
                .padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .background(TravelTheme.background)
            .navigationTitle("Share trip")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .task { if package == nil { prepare() } }
        .fileExporter(isPresented: $exporting, document: document, contentType: .travelViewTrip,
                      defaultFilename: "Travel View Trip") { result in
            if case .failure(let error) = result { self.error = error.localizedDescription }
        }
        .alert("Travel View", isPresented: Binding(get: { error != nil && package != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .sheet(isPresented: $sharingText) { ItineraryShareView(store: store, tripID: tripID) }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 680, minHeight: 600, idealHeight: 760)
        #endif
    }

    @ViewBuilder private func actions(_ document: TripFileDocument, title: String) -> some View {
        ShareLink(item: document, preview: SharePreview(title)) { Label("Send trip", systemImage: "square.and.arrow.up") }
            .buttonStyle(.borderedProminent).accessibilityIdentifier("share-trip-file")
        Button("Save a copy", systemImage: "doc.badge.arrow.up") { exporting = true }
            .buttonStyle(.bordered).accessibilityIdentifier("save-trip-file")
    }

    private var receivingHelp: some View {
        DisclosureGroup("Opening a received trip") {
            VStack(alignment: .leading, spacing: 10) {
                #if os(iOS)
                Text("Open the attachment in Messages or Mail and choose Travel View from the available open or share options. If it’s already in Files, tap the trip file there.")
                #else
                Text("Open the received trip file from Messages, Mail or Finder. AirDrop may save it in Downloads; open it there to start the review. If another app opens it, choose Open With → Travel View in Finder.")
                #endif
                Text("In Travel View, choose Review shared trip, then Import trip. You don’t need to find it again with the app’s Import shared trip menu.")
                Text("This is an independent copy. Later edits won’t update the other person’s trip.")
            }
            .font(.subheadline).foregroundStyle(TravelTheme.secondary).padding(.top, 10)
        }
        .accessibilityIdentifier("received-trip-help")
        .tripPanel()
    }

    private func prepare() {
        error = nil
        do {
            guard let trip = store.trips.first(where: { $0.id == tripID }) else { throw TripError("This trip is no longer available.") }
            let package = try SharedTripPackage(trip: trip, items: store.items(for: tripID), checklist: store.checklistItems(for: tripID))
            let document = try TripFileDocument(package: package)
            self.package = package; self.document = document
        } catch { self.error = error.localizedDescription }
    }
}

/// Reviewing a file makes no database changes. Import creates or opens its independent local copy.
struct SharedTripImportView: View {
    let store: TripStore
    let package: SharedTripPackage
    let onImported: (String) -> Void
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    private var existingID: String? { store.sharedTripImports[package.id] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(existingID == nil ? "Add an independent copy" : "This file was already imported").font(.headline)
                        Text(existingID == nil ? "Import this complete trip into your collection. Your existing trips stay as they are. Future edits to this copy belong to you." : "Open your existing copy, including any changes you’ve made since importing it.")
                            .font(.subheadline).foregroundStyle(TravelTheme.secondary)
                        if let loadError = store.loadError {
                            Text(loadError).foregroundStyle(TravelTheme.secondary)
                            Button("Try opening trips again") { Task { await store.load() } }
                        }
                        Button(action: importTrip) {
                            HStack {
                                if store.isWorking || store.isLoading { ProgressView() }
                                Text(existingID == nil ? "Import trip" : "Open imported trip")
                            }
                        }
                        .buttonStyle(.borderedProminent).disabled(!store.canChangeTrips)
                        .accessibilityIdentifier("confirm-trip-import")
                    }.tripPanel()
                    SharedTripPreview(package: package)
                }
                .padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .background(TravelTheme.background)
            .navigationTitle("Review shared trip")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(store.isWorking)
                }
            }
        }
        .interactiveDismissDisabled(store.isWorking)
        .alert("Couldn’t import trip", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 680, minHeight: 600, idealHeight: 760)
        #endif
    }

    private func importTrip() {
        Task {
            do { onImported(try await store.importSharedTrip(package)) }
            catch { self.error = error.localizedDescription }
        }
    }
}

private struct SharedTripPreview: View {
    let package: SharedTripPackage
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Trip details").font(.headline).accessibilityAddTraits(.isHeader)
            Text(package.trip.name).font(.title2.bold())
            Text("Travelers: \(package.trip.plannedTravelers) planned")
            Text("Budget: \(package.trip.budgetCents.map(Money.formatted) ?? "Not set")")
            Text("\(package.items.count) \(package.items.count == 1 ? "itinerary item" : "itinerary items")")
            Text("\(package.checklist.count) \(package.checklist.count == 1 ? "checklist item" : "checklist items")")
            Text("Exported \(package.exportedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(TravelTheme.secondary)
        }.tripPanel()
        VStack(alignment: .leading, spacing: 14) {
            Text("Itinerary preview").font(.headline).accessibilityAddTraits(.isHeader)
            Text(ItineraryText.make(trip: package.trip, items: package.items,
                                    options: ItineraryTextOptions(includeNotes: true, includeReferences: true, includeChecklist: true),
                                    checklist: package.checklist))
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }.tripPanel()
        let snapshots = package.items.filter { $0.flight?.lastLookup != nil }
        if !snapshots.isEmpty {
            DisclosureGroup("Saved flight lookups (\(snapshots.count))") {
                ForEach(snapshots) { item in
                    if let source = item.flight?.lastLookup {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title).font(.headline)
                            Text("\(source.provider) · \(source.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                            Text("Provider status at lookup: \(source.status)")
                        }.padding(.top, 10)
                    }
                }
            }.tripPanel()
        }
    }
}
