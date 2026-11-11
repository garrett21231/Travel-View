import SwiftUI
import TravelCore

struct TripOverview: View {
    let trip: Trip
    let store: TripStore
    let onEdit: () -> Void
    @State private var editor: ItemSelection?
    @State private var removing: ItineraryItem?
    @State private var error: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct ItemSelection: Identifiable {
        let id = UUID()
        let item: ItineraryItem?
        let kind: ItineraryKind
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(trip.name).font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("overview-trip-name")
                    Text(trip.destinationText).font(.title3).foregroundStyle(TravelTheme.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 16) {
                    Text("Trip details").font(.headline).accessibilityAddTraits(.isHeader)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        detail("Departure", value: trip.start?.formatted ?? "To be decided", symbol: "calendar")
                        detail("Return", value: trip.end?.formatted ?? "To be decided", symbol: "calendar.badge.checkmark")
                        detail("Travelers", value: "\(trip.plannedTravelers) planned", symbol: "person.2")
                        detail("Budget", value: trip.budgetCents.map(Money.formatted) ?? "Not set", symbol: "creditcard")
                    }
                }
                .tripPanel()

                itineraryPanel

                VStack(alignment: .leading, spacing: 10) {
                    Text("Notes").font(.headline).accessibilityAddTraits(.isHeader)
                    Text(trip.notes.isEmpty ? "No notes added." : trip.notes)
                        .foregroundStyle(trip.notes.isEmpty ? TravelTheme.secondary : TravelTheme.ink)
                        .textSelection(.enabled)
                }
                .tripPanel()
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(TravelTheme.background)
        .navigationTitle("Overview")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            Button("Edit trip", systemImage: "pencil", action: onEdit)
                .accessibilityIdentifier("edit-trip")
        }
        .sheet(item: $editor) { selection in
            ItineraryEditor(store: store, trip: trip, item: selection.item, kind: selection.kind)
        }
        .confirmationDialog("Remove this itinerary item?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Remove item", role: .destructive) {
                guard let item = removing else { return }
                Task {
                    do { try await store.deleteItem(item) }
                    catch { self.error = error.localizedDescription }
                    removing = nil
                }
            }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: { Text(removing?.title ?? "") }
        .alert("Travel View", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private var itineraryPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack { itineraryHeading; Spacer(); addMenu }
                VStack(alignment: .leading, spacing: 12) { itineraryHeading; addMenu }
            }
            let items = store.items(for: trip.id)
            if items.isEmpty {
                Text("Bring your plans together with flights, places to stay, and things to do.")
                    .foregroundStyle(TravelTheme.secondary)
            }
            ForEach(items) { item in
                Divider()
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.kind.symbol).foregroundStyle(TravelTheme.accent)
                        .frame(width: 24).padding(.top, 3).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(item.title).font(.headline)
                        Text(item.dateText).font(.subheadline).foregroundStyle(TravelTheme.secondary)
                        if let flight = item.flight {
                            Text("\(flight.number) · \(flight.departureAirport.isEmpty ? "TBD" : flight.departureAirport) → \(flight.arrivalAirport.isEmpty ? "TBD" : flight.arrivalAirport)")
                            if let departure = flight.departureLocal { Text("Departs \(departure.formatted)") }
                            if let arrival = flight.arrivalLocal { Text("Arrives \(arrival.formatted)") }
                            if flight.departureLocal != nil || flight.arrivalLocal != nil {
                                Text("Airport local times").font(.caption).foregroundStyle(TravelTheme.secondary)
                            }
                            if !flight.airline.isEmpty { Text(flight.airline) }
                            if !flight.bookingReference.isEmpty { Text("Booking reference: \(flight.bookingReference)") }
                            if let snapshot = flight.lastLookup {
                                Text("Schedule from \(snapshot.provider), looked up \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened)). Review with your airline before travel.")
                                    .font(.caption).foregroundStyle(TravelTheme.secondary)
                            }
                        }
                        if !item.location.isEmpty { Text(item.location) }
                        if !item.notes.isEmpty { Text(item.notes).foregroundStyle(TravelTheme.secondary) }
                    }
                    .font(.subheadline)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Menu {
                        Button("Edit", systemImage: "pencil") { editor = ItemSelection(item: item, kind: item.kind) }
                        Button("Remove", systemImage: "trash", role: .destructive) { removing = item }
                    } label: { Label("Actions for \(item.title)", systemImage: "ellipsis.circle").labelStyle(.iconOnly) }
                        .disabled(!store.canChangeTrips)
                }
            }
        }.tripPanel()
    }

    private var itineraryHeading: some View {
        Text("Itinerary").font(.headline).accessibilityAddTraits(.isHeader)
    }
    private var addMenu: some View {
        Menu {
            ForEach(ItineraryKind.allCases) { kind in
                Button(kind.title, systemImage: kind.symbol) { editor = ItemSelection(item: nil, kind: kind) }
            }
        } label: { Label("Add item", systemImage: "plus") }
            .disabled(!store.canChangeTrips)
            .accessibilityIdentifier("add-itinerary")
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), alignment: .topLeading),
              count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    private func detail(_ title: String, value: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(TravelTheme.accent).frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.caption).foregroundStyle(TravelTheme.secondary)
                Text(value).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    func tripPanel() -> some View {
        padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TravelTheme.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(TravelTheme.edge.opacity(0.4), lineWidth: 0.7) }
    }
}
