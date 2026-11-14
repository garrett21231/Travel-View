import SwiftUI
import TravelCore

struct ItineraryScheduleSelection: Hashable {
    let tripID: String
    var dayID: String? = nil
}

/// Day browsing changes only the visible timeline. Editing still uses the original item IDs.
struct ItineraryScheduleView: View {
    let store: TripStore
    let tripID: String
    @State private var selectedDayID: String?
    @State private var editor: EditorSelection?
    @State private var removing: ItineraryItem?
    @State private var checkingFlight: ItineraryItem?
    @State private var error: String?
    @State private var today = TravelDay()
    @Environment(\.scenePhase) private var scenePhase

    private struct EditorSelection: Identifiable {
        let id = UUID()
        let item: ItineraryItem?
        let kind: ItineraryKind
        var initialDay: TravelDay? = nil
    }

    init(store: TripStore, selection: ItineraryScheduleSelection) {
        self.store = store; tripID = selection.tripID
        _selectedDayID = State(initialValue: selection.dayID)
    }

    private var trip: Trip? { store.trips.first { $0.id == tripID } }
    private var navigation: ItineraryDayNavigation {
        ItineraryDayNavigation(items: store.items(for: tripID), selectedID: selectedDayID)
    }

    var body: some View {
        let navigation = navigation
        Group {
            if let trip {
                VStack(spacing: 0) {
                    if !navigation.days.isEmpty {
                        dayControls(navigation, trip: trip)
                            .padding(20)
                            .frame(maxWidth: 760)
                        Divider()
                    }
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            if navigation.days.isEmpty {
                                ContentUnavailableView("No plans yet", systemImage: "calendar.badge.plus",
                                    description: Text("Add a flight, transport, stay, or activity to start your itinerary."))
                            } else {
                                ForEach(navigation.visibleDays) { day in
                                    ItineraryDayView(group: day, today: today, canEdit: store.canChangeTrips,
                                        onEdit: { editor = EditorSelection(item: $0, kind: $0.kind) },
                                        onRemove: { removing = $0 }, onCheckFlight: checkFlight)
                                }
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: 760)
                        .frame(maxWidth: .infinity)
                    }
                    // Start a newly selected day at the top; visiting details keeps the selection.
                    .id(navigation.selectedID ?? "all")
                }
            } else {
                ContentUnavailableView("This trip is no longer available", systemImage: "suitcase.rolling")
            }
        }
        .background(TravelTheme.background)
        .navigationTitle("Itinerary")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if trip != nil {
                Menu {
                    ForEach(ItineraryKind.allCases) { kind in
                        Button(kind.title, systemImage: kind.symbol) {
                            editor = EditorSelection(item: nil, kind: kind, initialDay: navigation.selectedDay?.day)
                        }
                    }
                } label: { Label("Add item", systemImage: "plus") }
                    .disabled(!store.canChangeTrips)
                    .accessibilityIdentifier("add-schedule-item")
            }
        }
        .sheet(item: $editor) { selection in
            if let trip {
                ItineraryEditor(store: store, trip: trip, item: selection.item, kind: selection.kind, initialDay: selection.initialDay)
            }
        }
        .sheet(item: $checkingFlight) { item in FlightUpdateView(store: store, item: item) }
        .confirmationDialog("Remove this itinerary item?",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Remove item", role: .destructive) {
                guard let item = removing else { return }
                Task {
                    do { try await store.deleteItem(item) }
                    catch { self.error = error.localizedDescription }
                    removing = nil
                }
            }.disabled(!store.canChangeTrips)
            Button("Cancel", role: .cancel) { removing = nil }
        } message: { Text(removing?.title ?? "") }
        .alert("Travel View", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .onChange(of: navigation.days.map(\.id)) { _, _ in
            // A date edit or removal can empty the chosen day. Show the remaining plans instead of a stale filter.
            selectedDayID = navigation.selectedID
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { today = TravelDay() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in today = TravelDay() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in today = TravelDay() }
    }

    private func dayControls(_ navigation: ItineraryDayNavigation, trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(trip.name).font(.subheadline).foregroundStyle(TravelTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    dayPicker(navigation)
                    Spacer(minLength: 0)
                    dayButtons(navigation)
                }
                VStack(alignment: .leading, spacing: 10) {
                    dayPicker(navigation)
                    dayButtons(navigation)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack { planCount(navigation); Spacer(); browsePlans }
                VStack(alignment: .leading, spacing: 10) { planCount(navigation); browsePlans }
            }
            Text("Times are local to each location. Only days with saved plans are listed.")
                .font(.caption).foregroundStyle(TravelTheme.secondary)
        }
    }

    private func dayPicker(_ navigation: ItineraryDayNavigation) -> some View {
        Picker("Day", selection: Binding(get: { navigation.selectedID }, set: { selectedDayID = $0 })) {
            Text("All days").tag(nil as String?)
            ForEach(navigation.days) { day in
                Text(day.day?.formatted ?? "Undated plans").tag(day.id as String?)
            }
        }
        .pickerStyle(.menu).fixedSize(horizontal: true, vertical: true)
        .accessibilityIdentifier("itinerary-day-picker")
    }

    @ViewBuilder private func dayButtons(_ navigation: ItineraryDayNavigation) -> some View {
        if navigation.selectedID != nil {
            HStack(spacing: 12) {
                Button("Previous planned day", systemImage: "chevron.left") { selectedDayID = navigation.previousID }
                    .labelStyle(.iconOnly).buttonStyle(.bordered)
                    .disabled(navigation.previousID == nil).accessibilityIdentifier("previous-itinerary-day")
                Button(navigation.nextID == "undated" ? "View undated plans" : "Next planned day", systemImage: "chevron.right") {
                    selectedDayID = navigation.nextID
                }
                .labelStyle(.iconOnly).buttonStyle(.bordered)
                .disabled(navigation.nextID == nil).accessibilityIdentifier("next-itinerary-day")
            }
        }
    }

    private func planCount(_ navigation: ItineraryDayNavigation) -> some View {
        Text(navigation.selectedID == nil ? "\(navigation.totalPlans) \(navigation.totalPlans == 1 ? "plan" : "plans")" :
            "\(navigation.visiblePlans) of \(navigation.totalPlans) \(navigation.totalPlans == 1 ? "plan" : "plans")")
            .font(.subheadline.weight(.medium)).accessibilityIdentifier("schedule-plan-count")
    }

    private var browsePlans: some View {
        NavigationLink(value: ItineraryBrowserSelection(tripID: tripID)) {
            Label("Find a plan", systemImage: "magnifyingglass")
        }.buttonStyle(.bordered)
    }

    private func checkFlight(_ item: ItineraryItem) {
        if item.start == nil { error = "Edit the flight and add its departure date before checking for updates." }
        else { checkingFlight = item }
    }
}
