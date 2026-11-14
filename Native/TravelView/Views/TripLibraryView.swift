import SwiftUI
import TravelCore

/// NavigationSplitView becomes a push navigation flow on iPhone and a sidebar on Mac.
struct TripLibraryView: View {
    let store: TripStore
    @State private var collection = Collection.upcoming
    @State private var selectedTripID: String?
    @State private var compactColumn = NavigationSplitViewColumn.sidebar
    @State private var editor: EditorSelection?
    @State private var today = TravelDay()
    @State private var importing = false
    @State private var exporting = false
    @State private var exportDocument = TripBackupDocument(data: Data())
    @State private var notice: String?
    @State private var importKind = ImportKind.backup
    @State private var pendingPackage: SharedTripPackage?
    @State private var reviewingPackage: SharedTripPackage?
    @State private var readingSharedTrip = false
    @State private var readTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    private enum Collection: String, CaseIterable, Identifiable {
        case upcoming = "Upcoming", all = "All trips"
        var id: Self { self }
    }

    private enum ImportKind { case backup, sharedTrip }

    private struct EditorSelection: Identifiable {
        let id = UUID()
        let trip: Trip?
    }

    private var visibleTrips: [Trip] {
        collection == .upcoming ? Trip.upcoming(store.trips, on: today) : store.trips.sorted {
            ($0.createdAt, $0.id) > ($1.createdAt, $1.id)
        }
    }

    private var selectedTrip: Trip? { store.trips.first { $0.id == selectedTripID } }

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView(preferredCompactColumn: $compactColumn) {
                VStack(spacing: 0) {
                    Picker("Trip collection", selection: $collection) {
                        ForEach(Collection.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)

                    if store.isLoading {
                        ProgressView("Loading your trips…").frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let error = store.loadError {
                        ContentUnavailableView {
                            Label("Couldn’t open trips", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(error)
                        } actions: {
                            Button("Try again") { Task { await store.load() } }
                        }
                    } else if visibleTrips.isEmpty {
                        emptyState
                    } else {
                        tripList
                    }
                }
                .background(TravelTheme.background)
                .navigationTitle(collection == .upcoming ? "Upcoming trips" : "All trips")
                .navigationSplitViewColumnWidth(min: 300, ideal: 350, max: 440)
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Menu {
                            Button("Import shared trip", systemImage: "suitcase.rolling") { importKind = .sharedTrip; importing = true }
                            Divider()
                            Button("Export trips", systemImage: "square.and.arrow.up", action: exportTrips)
                                .disabled(store.trips.isEmpty)
                            Button("Import backup", systemImage: "square.and.arrow.down") { importKind = .backup; importing = true }
                        } label: {
                            Label("Trip files and backups", systemImage: "ellipsis.circle")
                        }
                        .disabled(!store.canChangeTrips)
                        Button("New trip", systemImage: "plus") { editor = EditorSelection(trip: nil) }
                            .disabled(!store.canChangeTrips)
                            .accessibilityIdentifier("new-trip")
                    }
                }
            } detail: {
                if let trip = selectedTrip {
                    NavigationStack {
                        TripOverview(trip: trip, store: store) { editor = EditorSelection(trip: trip) }
                            .navigationDestination(for: ItinerarySelection.self) { selection in
                                ItineraryDetailView(store: store, tripID: selection.tripID, itemID: selection.id)
                            }
                            .navigationDestination(for: ItineraryBrowserSelection.self) { selection in
                                ItineraryBrowserView(store: store, selection: selection)
                            }
                    }
                    .id(trip.id)
                } else {
                    ContentUnavailableView("Your next adventure", systemImage: "suitcase.rolling",
                                           description: Text("Choose a trip or start planning a new one."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(TravelTheme.background)
                }
            }
            .navigationSplitViewStyle(.balanced)
            incomingTripBanner
        }
        .sheet(item: $reviewingPackage) { package in
            SharedTripImportView(store: store, package: package) { id in
                collection = .all
                selectedTripID = id
                compactColumn = .detail
                if pendingPackage?.id == package.id { pendingPackage = nil }
                reviewingPackage = nil
            }
        }
        .sheet(item: $editor) { selection in
            TripEditor(store: store, trip: selection.trip) { saved in
                if let end = saved.end, end < today { collection = .all }
                selectedTripID = saved.id
                compactColumn = .detail
            }
        }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json,
                      defaultFilename: "Travel View Backup") { result in
            if case .failure(let error) = result { notice = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: importKind == .backup ? [.json] : [.travelViewTrip]) { result in
            switch result {
            case .success(let url):
                if importKind == .backup { importTrips(from: url) }
                else { readSharedTrip(from: url) }
            case .failure(let error): notice = error.localizedDescription
            }
        }
        .alert("Travel View", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK") { notice = nil }
        } message: { Text(notice ?? "") }
        .task { await store.load() }
        .onOpenURL { readSharedTrip(from: $0) }
        .onChange(of: collection) { _, _ in
            if !visibleTrips.contains(where: { $0.id == selectedTripID }) { selectedTripID = nil }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { today = TravelDay() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in today = TravelDay() }
    }

    /// Outside the split view so it remains visible in either compact column on iPhone.
    @ViewBuilder private var incomingTripBanner: some View {
        if let package = pendingPackage {
            VStack(alignment: .leading, spacing: 10) {
                Text("Trip file ready: \(package.trip.name)").font(.subheadline.weight(.semibold))
                HStack {
                    Button("Review shared trip") { reviewingPackage = package }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("review-shared-trip")
                    Button("Dismiss") { pendingPackage = nil }
                }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(TravelTheme.surface)
        } else if readingSharedTrip { ProgressView("Reading shared trip…").padding(14) }
    }

    private var tripList: some View {
        List(selection: $selectedTripID) {
            Section {
                ForEach(visibleTrips) { trip in
                    NavigationLink(value: trip.id) {
                        TripRow(trip: trip, today: today, selected: trip.id == selectedTripID)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("trip-\(trip.id)")
                }
            } header: {
                Text("\(visibleTrips.count) \(visibleTrips.count == 1 ? "trip" : "trips")")
                    .foregroundStyle(TravelTheme.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.sidebar)
        #endif
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(collection == .upcoming ? "Where to next?" : "Your trips, all together", systemImage: "suitcase.rolling")
        } description: {
            Text(collection == .upcoming ? "Your upcoming trips and open plans will appear here." : "Save a trip to start your travel collection.")
        } actions: {
            Button("New trip", systemImage: "plus") { editor = EditorSelection(trip: nil) }
                .buttonStyle(.borderedProminent)
                .disabled(!store.canChangeTrips)
        }
    }

    private func exportTrips() {
        do {
            exportDocument = TripBackupDocument(data: try TripArchive.encode(store.trips, items: store.itinerary))
            exporting = true
        } catch { notice = error.localizedDescription }
    }

    /// A pending-file banner lets an open editor keep its draft until the user is ready to review.
    private func readSharedTrip(from url: URL) {
        readTask?.cancel()
        readingSharedTrip = true
        readTask = Task {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let package = try await Task.detached(priority: .userInitiated) {
                    try SharedTripPackage.decode(TripFileReader.read(url))
                }.value
                guard !Task.isCancelled else { return }
                pendingPackage = package
            } catch {
                guard !Task.isCancelled else { return }
                notice = (error as? TripError)?.message ?? "The trip file couldn’t be opened. Download it to this device and try again."
            }
            readingSharedTrip = false
        }
    }

    private func importTrips(from url: URL) {
        Task {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= TripArchive.maximumBytes else { throw TripError("Choose a backup smaller than 10 MB.") }
                    return try Data(contentsOf: url)
                }.value
                let result = try await store.restore(data)
                collection = .all
                notice = "Imported \(result.added) trips and \(result.addedItems) itinerary items. Existing records keep their current details."
            } catch { notice = error.localizedDescription }
        }
    }
}

private struct TripRow: View {
    let trip: Trip
    let today: TravelDay
    let selected: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "suitcase.rolling")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .foregroundStyle(TravelTheme.accent)
                    .background(TravelTheme.tint, in: RoundedRectangle(cornerRadius: 11))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(trip.name).font(.headline).foregroundStyle(TravelTheme.ink)
                if trip.isInProgress(on: today) {
                    Label("In progress", systemImage: "location.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(TravelTheme.accent)
                }
                Text(trip.destinationText)
                Text(trip.dateText)
            }
            .font(.caption)
            .foregroundStyle(TravelTheme.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(TravelTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(selected ? TravelTheme.accent : TravelTheme.edge.opacity(0.4), lineWidth: selected ? 1.5 : 0.7)
        }
        .accessibilityElement(children: .combine)
    }
}
