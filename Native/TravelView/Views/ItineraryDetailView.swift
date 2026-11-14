import SwiftUI
import TravelCore

/// Navigation carries IDs so the page keeps reading the latest committed item from the store.
struct ItinerarySelection: Hashable {
    let id: String
    let tripID: String
}

struct ItineraryDetailView: View {
    let store: TripStore
    let tripID: String
    let itemID: String
    @State private var editing: ItineraryItem?
    @State private var checking: ItineraryItem?
    @State private var removing = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    private var trip: Trip? { store.trips.first { $0.id == tripID } }
    private var item: ItineraryItem? { store.itinerary.first { $0.id == itemID && $0.tripID == tripID } }

    var body: some View {
        Group {
            if let item, trip != nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(item.title).font(.largeTitle.bold())
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityIdentifier("itinerary-detail-title")
                            HStack(spacing: 12) {
                                Label(item.transport?.mode.title ?? item.kind.title, systemImage: item.symbol).foregroundStyle(TravelTheme.secondary)
                                BookingStateBadge(state: item.bookingState)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        reservation(item)
                        schedule(item)
                        if let transport = item.transport { transportLocations(transport) }
                        else { location(item) }
                        VStack(alignment: .leading, spacing: 10) {
                            heading("Notes")
                            Text(item.notes.isEmpty ? "No notes added." : item.notes)
                                .foregroundStyle(item.notes.isEmpty ? TravelTheme.secondary : TravelTheme.ink)
                                .textSelection(.enabled)
                        }.tripPanel()
                        if let source = item.flight?.lastLookup {
                            VStack(alignment: .leading, spacing: 10) {
                                heading("Saved flight lookup")
                                Text(source.provider)
                                Text(source.fetchedAt.formatted(date: .abbreviated, time: .shortened))
                                Text("Provider status at lookup: \(source.status)")
                                Text("This is a dated snapshot. Review the schedule with your airline before travel.")
                                    .font(.caption).foregroundStyle(TravelTheme.secondary)
                            }.tripPanel()
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
            } else {
                ContentUnavailableView {
                    Label("This plan is no longer available", systemImage: "calendar.badge.exclamationmark")
                } description: { Text("Return to the itinerary to see your current plans.") } actions: {
                    Button("Back to itinerary") { dismiss() }
                }
            }
        }
        .background(TravelTheme.background)
        .navigationTitle(item?.kind.title ?? "Plan")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if let item, trip != nil {
                Button("Edit", systemImage: "pencil") { editing = item }
                    .disabled(!store.canChangeTrips).accessibilityIdentifier("edit-itinerary-detail")
                Menu {
                    if item.kind == .flight {
                        Button("Check flight updates", systemImage: "arrow.clockwise") {
                            if item.start == nil { error = "Add a departure date in Edit before checking for updates." }
                            else { checking = item }
                        }
                    }
                    Button("Remove item", systemImage: "trash", role: .destructive) { removing = true }
                } label: { Label("Plan actions", systemImage: "ellipsis.circle") }
                    .disabled(!store.canChangeTrips)
            }
        }
        .sheet(item: $editing) { item in
            if let trip { ItineraryEditor(store: store, trip: trip, item: item) }
        }
        .sheet(item: $checking) { item in FlightUpdateView(store: store, item: item) }
        .confirmationDialog("Remove this itinerary item?", isPresented: $removing, titleVisibility: .visible) {
            Button("Remove item", role: .destructive) {
                guard let item else { return }
                Task {
                    do { try await store.deleteItem(item); dismiss() }
                    catch { self.error = error.localizedDescription }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text(item?.title ?? "") }
        .alert("Travel View", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func reservation(_ item: ItineraryItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("Reservation")
            Text(item.kind == .flight ? "Booking reference" : "Confirmation reference")
                .font(.caption).foregroundStyle(TravelTheme.secondary)
            Text(item.confirmationReference.isEmpty ? "Not added" : item.confirmationReference)
                .textSelection(.enabled)
                .accessibilityIdentifier("itinerary-detail-reference")
        }.tripPanel()
    }

    private func schedule(_ item: ItineraryItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Schedule")
            if let flight = item.flight {
                Text("\(flight.number) · \(flight.airline.isEmpty ? "Airline not added" : flight.airline)")
                scheduleField("Departure · \(airport(flight.departureAirport))", day: item.start,
                              time: flight.departureLocal.flatMap { LocalClock(rawValue: $0.clock) })
                scheduleField("Arrival · \(airport(flight.arrivalAirport))", day: item.end,
                              time: flight.arrivalLocal.flatMap { LocalClock(rawValue: $0.clock) })
                Text("Each time is local to its airport.").font(.caption).foregroundStyle(TravelTheme.secondary)
            } else if let transport = item.transport {
                Text(transport.mode.title + (transport.operatorName.isEmpty ? "" : " · " + transport.operatorName))
                scheduleField("Departure", day: item.start, time: item.startTime)
                scheduleField("Arrival", day: item.end, time: item.endTime)
                Text("Each time is local to its stop. Times are not converted between time zones.")
                    .font(.caption).foregroundStyle(TravelTheme.secondary)
            } else {
                scheduleField(item.kind == .lodging ? "Check-in" : "Start", day: item.start, time: item.startTime)
                scheduleField(item.kind == .lodging ? "Check-out" : "End", day: item.end, time: item.endTime)
                Text("Times are local to this location.").font(.caption).foregroundStyle(TravelTheme.secondary)
            }
        }.tripPanel()
    }

    private func transportLocations(_ transport: TransportDetails) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Route")
            transportStop("Departure", location: transport.departure)
            transportStop("Arrival", location: transport.arrival)
        }.tripPanel()
    }

    private func transportStop(_ title: String, location: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(TravelTheme.secondary)
            Text(location.isEmpty ? "Location to be decided" : location).textSelection(.enabled)
            if let url = LocationLink.mapsSearch(for: location) {
                Link(destination: url) { Label("Open \(title.lowercased()) in Maps", systemImage: "map") }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func location(_ item: ItineraryItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Location")
            Text(item.location.isEmpty ? "No location added." : item.location)
                .foregroundStyle(item.location.isEmpty ? TravelTheme.secondary : TravelTheme.ink)
                .textSelection(.enabled)
            if let url = item.mapsURL {
                Link(destination: url) { Label("Open in Maps", systemImage: "map") }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("open-itinerary-maps")
            }
        }.tripPanel()
    }

    private func heading(_ title: String) -> some View { Text(title).font(.headline).accessibilityAddTraits(.isHeader) }
    private func airport(_ code: String) -> String { code.isEmpty ? "Airport to be decided" : code }
    private func scheduleField(_ title: String, day: TravelDay?, time: LocalClock?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(TravelTheme.secondary)
            Text(day?.formatted ?? "Date to be decided")
            Text(time?.rawValue ?? "Time to be decided").foregroundStyle(time == nil ? TravelTheme.secondary : TravelTheme.ink)
        }.accessibilityElement(children: .combine)
    }
}

struct BookingStateBadge: View {
    let state: BookingState
    var body: some View {
        Label(state.title, systemImage: state.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(TravelTheme.accent)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(TravelTheme.tint, in: Capsule())
            .accessibilityLabel("Booking state: \(state.title)")
    }
}
