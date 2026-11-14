import SwiftUI
import TravelCore

/// Recovery and permanent deletion both publish only after their database transaction commits.
struct RecentlyDeletedView: View {
    let store: TripStore
    let onRestored: (String) -> Void
    @State private var restoringID: String?
    @State private var deletingID: String?
    @State private var alert: TripAlert?
    @Environment(\.dismiss) private var dismiss

    private enum TripAlert {
        case confirmDeletion(DeletedTrip)
        case failure(title: String, message: String)

        var title: String {
            switch self {
            case .confirmDeletion(let trip): "Permanently delete “\(trip.name)”?"
            case .failure(let title, _): title
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.deletedTrips.isEmpty {
                    ContentUnavailableView("No deleted trips", systemImage: "trash",
                                           description: Text("Trips you delete can be restored here with all their saved plans."))
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(store.deletedTrips) { trip in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(trip.name).font(.headline)
                                    Text("\(trip.itemCount) \(trip.itemCount == 1 ? "itinerary item" : "itinerary items") · Deleted \(trip.deletedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption).foregroundStyle(TravelTheme.secondary)
                                    ViewThatFits(in: .horizontal) {
                                        HStack(spacing: 12) { actions(for: trip) }
                                            .fixedSize(horizontal: true, vertical: false)
                                        VStack(alignment: .leading, spacing: 10) { actions(for: trip) }
                                    }
                                }
                                .tripPanel()
                                .accessibilityElement(children: .contain)
                            }
                            Text("Trips stay here until restored or permanently deleted. Backups and sharing include only trips in your collection.")
                                .font(.caption).foregroundStyle(TravelTheme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(20)
                    }
                }
            }
            .background(TravelTheme.background)
            .navigationTitle("Recently deleted")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.disabled(store.isWorking)
                }
            }
        }
        .interactiveDismissDisabled(store.isWorking)
        .alert(alert?.title ?? "Travel View",
               isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } }),
               presenting: alert) { selection in
            switch selection {
            case .confirmDeletion(let trip):
                Button("Delete permanently", role: .destructive) { permanentlyDelete(trip) }
                    .disabled(!store.canChangeTrips)
                    .accessibilityIdentifier("confirm-permanent-trip-deletion")
                Button("Cancel", role: .cancel) {}
            case .failure:
                Button("OK", role: .cancel) {}
            }
        } message: { selection in
            switch selection {
            case .confirmDeletion:
                Text("This trip and all its saved plans will be removed from Recently deleted on this device. This can’t be undone. Existing backup files and copies shared with others are kept.")
            case .failure(_, let message): Text(message)
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 580, minHeight: 420, idealHeight: 600)
        #endif
    }

    @ViewBuilder private func actions(for trip: DeletedTrip) -> some View {
        Button { restore(trip) } label: {
            HStack {
                if restoringID == trip.id { ProgressView() }
                Label("Restore trip", systemImage: "arrow.uturn.backward")
            }
        }
        .buttonStyle(.bordered)
        .disabled(!store.canChangeTrips)
        .accessibilityIdentifier("restore-trip-\(trip.id)")
        .accessibilityLabel("Restore \(trip.name)")
        .accessibilityHint("Returns this trip and all its saved plans to your collection.")

        Button(role: .destructive) { alert = .confirmDeletion(trip) } label: {
            HStack {
                if deletingID == trip.id { ProgressView() }
                Label("Delete permanently", systemImage: "trash")
            }
        }
        .buttonStyle(.bordered).tint(.red).foregroundStyle(.red)
        .disabled(!store.canChangeTrips)
        .accessibilityIdentifier("permanently-delete-trip-\(trip.id)")
        .accessibilityLabel("Permanently delete \(trip.name)")
        .accessibilityHint("Asks for confirmation before removing this trip from Recently deleted.")
    }

    private func restore(_ trip: DeletedTrip) {
        restoringID = trip.id
        Task {
            defer { restoringID = nil }
            do { onRestored(try await store.restoreDeletedTrip(trip)) }
            catch { alert = .failure(title: "Couldn’t restore trip", message: error.localizedDescription) }
        }
    }

    private func permanentlyDelete(_ trip: DeletedTrip) {
        alert = nil
        deletingID = trip.id
        Task {
            defer { deletingID = nil }
            do { try await store.permanentlyDeleteTrip(trip) }
            catch { alert = .failure(title: "Couldn’t delete trip", message: error.localizedDescription) }
        }
    }
}
