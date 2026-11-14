import SwiftUI
import TravelCore

/// Deletion is recoverable on this device. Restore publishes only after the entire trip commits.
struct RecentlyDeletedView: View {
    let store: TripStore
    let onRestored: (String) -> Void
    @State private var restoringID: String?
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

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
                                    Button {
                                        restore(trip)
                                    } label: {
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
                                }
                                .tripPanel()
                                .accessibilityElement(children: .contain)
                            }
                            Text("Deleted trips stay on this device until you restore them. Backups and sharing include only trips in your collection.")
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
        .alert("Couldn’t restore trip", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 580, minHeight: 420, idealHeight: 600)
        #endif
    }

    private func restore(_ trip: DeletedTrip) {
        restoringID = trip.id
        Task {
            defer { restoringID = nil }
            do { onRestored(try await store.restoreDeletedTrip(trip)) }
            catch { self.error = error.localizedDescription }
        }
    }
}
