import SwiftUI
import TravelCore

struct TripOverview: View {
    let trip: Trip
    let store: TripStore
    let onEdit: () -> Void
    @State private var editor: ItemSelection?
    @State private var removing: ItineraryItem?
    @State private var checkingFlight: ItineraryItem?
    @State private var error: String?
    @State private var today = TravelDay()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct ItemSelection: Identifiable {
        let id = UUID()
        let item: ItineraryItem?
        let kind: ItineraryKind
    }

    var body: some View {
        let days = ItineraryTimeline.days(for: store.items(for: trip.id))
        ScrollViewReader { proxy in
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

                    if !days.isEmpty { comingUp(days: days, proxy: proxy) }
                    itineraryPanel(days: days)

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
        }
        .background(TravelTheme.background)
        .navigationTitle("Overview")
        .navigationDestination(for: ItinerarySelection.self) { selection in
            ItineraryDetailView(store: store, tripID: selection.tripID, itemID: selection.id)
        }
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
        .sheet(item: $checkingFlight) { item in
            FlightUpdateView(store: store, item: item)
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { today = TravelDay() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in today = TravelDay() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in today = TravelDay() }
    }

    private func itineraryPanel(days: [ItineraryDay]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack { itineraryHeading; Spacer(); addMenu }
                VStack(alignment: .leading, spacing: 12) { itineraryHeading; addMenu }
            }
            if days.isEmpty {
                Text("Bring your plans together with flights, places to stay, and things to do.")
                    .foregroundStyle(TravelTheme.secondary)
                    .tripPanel()
            } else {
                Text("Times are local to each location. Plans with a time appear first within each day.")
                    .font(.caption).foregroundStyle(TravelTheme.secondary)
            }
            ForEach(days) { day in
                ItineraryDayView(group: day, today: today, canEdit: store.canChangeTrips,
                                 onEdit: { editor = ItemSelection(item: $0, kind: $0.kind) },
                                 onRemove: { removing = $0 }, onCheckFlight: { item in
                                     if item.start == nil {
                                         error = "Edit the flight and add its departure date before checking for updates."
                                     } else { checkingFlight = item }
                                 })
            }
        }
    }

    private func comingUp(days: [ItineraryDay], proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Coming up").font(.headline).accessibilityAddTraits(.isHeader)
            if let next = ItineraryTimeline.upcomingDay(in: days, on: today), let date = next.day {
                Text(date == today ? "Today’s schedule" : "Next planned day").font(.caption).foregroundStyle(TravelTheme.secondary)
                Text(date.formatted).font(.title3.weight(.semibold))
                ForEach(next.events.prefix(2)) { event in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.item.title).font(.subheadline.weight(.medium))
                        Text("\(event.title) · \(event.timeText)").font(.caption).foregroundStyle(TravelTheme.secondary)
                    }
                }
                if next.events.count > 2 {
                    Text("+\(next.events.count - 2) more on this day").font(.caption).foregroundStyle(TravelTheme.secondary)
                }
                Button("View day", systemImage: "calendar") {
                    withAnimation { proxy.scrollTo(next.id, anchor: .top) }
                }.buttonStyle(.bordered)
            } else if days.contains(where: { $0.day == nil }) {
                Text("Your open plans are ready for dates.").foregroundStyle(TravelTheme.secondary)
                Button("View undated plans", systemImage: "calendar.badge.questionmark") {
                    withAnimation { proxy.scrollTo("undated", anchor: .top) }
                }.buttonStyle(.bordered)
            } else {
                Text("No more dated plans ahead. Your earlier plans are in the itinerary below.")
                    .foregroundStyle(TravelTheme.secondary)
            }
        }
        .tripPanel()
        .accessibilityIdentifier("coming-up")
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
