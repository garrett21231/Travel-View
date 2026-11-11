import SwiftUI
import TravelCore

/// The entire draft stays in this sheet, including a flight selected from lookup.
struct ItineraryEditor: View {
    let store: TripStore
    let trip: Trip
    private let item: ItineraryItem?
    @State private var itemID: String
    private let initial: Draft
    @State private var draft: Draft
    @State private var lookup = false
    @State private var discard = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    private struct Draft: Equatable {
        var kind: ItineraryKind
        var title: String
        var location: String
        var notes: String
        var hasDates: Bool
        var hasArrivalDate: Bool
        var start: Date
        var end: Date
        var flight: FlightDetails
        var hasDepartureTime: Bool
        var hasArrivalTime: Bool
        var departureTime: Date
        var arrivalTime: Date

        init(trip: Trip, item: ItineraryItem?, kind: ItineraryKind) {
            self.kind = item?.kind ?? kind
            title = item?.title ?? ""
            location = item?.location ?? ""
            notes = item?.notes ?? ""
            hasDates = item?.start != nil
            hasArrivalDate = item == nil || item?.end != nil
            start = (item?.start ?? trip.start ?? TravelDay()).date()
            end = (item?.end ?? item?.start ?? trip.start ?? TravelDay()).date()
            flight = item?.flight ?? FlightDetails()
            hasDepartureTime = flight.departureLocal != nil
            hasArrivalTime = flight.arrivalLocal != nil
            departureTime = flight.departureLocal?.pickerDate ?? LocalMoment(rawValue: "2026-01-01T12:00")!.pickerDate
            arrivalTime = flight.arrivalLocal?.pickerDate ?? LocalMoment(rawValue: "2026-01-01T14:00")!.pickerDate
        }

        mutating func choose(_ schedule: FlightSchedule, queryDay: TravelDay) {
            let reference = flight.bookingReference
            flight = FlightDetails(schedule: schedule)
            flight.bookingReference = reference
            title = "\(schedule.number) · \(schedule.departure.airport) to \(schedule.arrival.airport)"
            hasDates = true
            hasArrivalDate = schedule.arrival.local != nil
            start = (schedule.departure.local?.day ?? queryDay).date()
            end = (schedule.arrival.local?.day ?? schedule.departure.local?.day ?? queryDay).date()
            hasDepartureTime = schedule.departure.local != nil
            hasArrivalTime = schedule.arrival.local != nil
            if let local = schedule.departure.local { departureTime = local.pickerDate }
            if let local = schedule.arrival.local { arrivalTime = local.pickerDate }
        }

        func input() -> ItineraryInput {
            var details = flight
            details.departureLocal = hasDates && hasDepartureTime ? LocalMoment(day: TravelDay(start), clockFrom: departureTime) : nil
            details.arrivalLocal = hasDates && hasArrivalDate && hasArrivalTime ? LocalMoment(day: TravelDay(end), clockFrom: arrivalTime) : nil
            return ItineraryInput(kind: kind, title: title, start: hasDates ? TravelDay(start) : nil,
                                  end: hasDates && (kind != .flight || hasArrivalDate) ? TravelDay(end) : nil, location: location, notes: notes,
                                  flight: kind == .flight ? details : nil)
        }
    }

    init(store: TripStore, trip: Trip, item: ItineraryItem? = nil, kind: ItineraryKind = .activity) {
        self.store = store; self.trip = trip; self.item = item
        _itemID = State(initialValue: item?.id ?? UUID().uuidString)
        let draft = Draft(trip: trip, item: item, kind: kind)
        initial = draft
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Plan") {
                    if item == nil {
                        Picker("Type", selection: $draft.kind) {
                            ForEach(ItineraryKind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                        }
                    }
                    TextField("Title", text: $draft.title).focused($focused)
                        .accessibilityIdentifier("itinerary-title")
                    if draft.kind != .flight {
                        TextField("Location or address (optional)", text: $draft.location).focused($focused)
                    }
                }
                if draft.kind == .flight { flightFields }
                Section {
                    Toggle("Add dates", isOn: $draft.hasDates)
                    if draft.hasDates {
                        DatePicker(draft.kind == .lodging ? "Check-in" : draft.kind == .flight ? "Departure day" : "Start",
                                   selection: $draft.start, displayedComponents: .date)
                        if draft.kind == .flight { Toggle("Add arrival date", isOn: $draft.hasArrivalDate) }
                        if draft.kind != .flight || draft.hasArrivalDate {
                            DatePicker(draft.kind == .lodging ? "Check-out" : draft.kind == .flight ? "Arrival day" : "End",
                                       selection: $draft.end, displayedComponents: .date)
                        }
                        if draft.kind == .flight {
                            Toggle("Add departure time", isOn: $draft.hasDepartureTime)
                            if draft.hasDepartureTime {
                                DatePicker("Departure time", selection: $draft.departureTime, displayedComponents: .hourAndMinute)
                                    .environment(\.timeZone, LocalMoment.pickerTimeZone)
                                    .accessibilityValue(LocalMoment(day: TravelDay(draft.start), clockFrom: draft.departureTime).clock + " airport local time")
                            }
                            if draft.hasArrivalDate { Toggle("Add arrival time", isOn: $draft.hasArrivalTime) }
                            if draft.hasArrivalDate && draft.hasArrivalTime {
                                DatePicker("Arrival time", selection: $draft.arrivalTime, displayedComponents: .hourAndMinute)
                                    .environment(\.timeZone, LocalMoment.pickerTimeZone)
                                    .accessibilityValue(LocalMoment(day: TravelDay(draft.end), clockFrom: draft.arrivalTime).clock + " airport local time")
                            }
                        }
                    }
                } header: { Text("Schedule") } footer: {
                    Text(draft.kind == .flight ? "Use each airport’s local date and time. Arrival can be on a different day." : "Leave dates open until your plans are ready.")
                }
                Section("Notes") {
                    TextField("Details to remember", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...6).focused($focused)
                }
                Section {
                    Button(action: save) {
                        HStack {
                            if store.isWorking { ProgressView() }
                            Text(item == nil ? "Add to itinerary" : "Save changes").fontWeight(.semibold)
                        }.frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("save-itinerary")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(TravelTheme.background)
            .disabled(store.isWorking)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(item == nil ? "New itinerary item" : "Edit \(draft.kind.title.lowercased())")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        focused = false
                        if draft != initial { discard = true } else { dismiss() }
                    }.disabled(store.isWorking)
                }
                #if os(iOS)
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }
                }
                #endif
            }
        }
        .sheet(isPresented: $lookup) {
            FlightLookupView(number: draft.flight.number, day: TravelDay(draft.start)) { schedule, day in
                draft.choose(schedule, queryDay: day)
            }
        }
        .interactiveDismissDisabled(draft != initial || store.isWorking)
        .confirmationDialog("Discard your changes?", isPresented: $discard, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
        .alert("Couldn’t save itinerary item", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        #if os(macOS)
        .frame(minWidth: 490, idealWidth: 560, minHeight: 600, idealHeight: 740)
        #endif
    }

    private var flightFields: some View {
        Section {
            Button("Find flight details", systemImage: "magnifyingglass") { focused = false; lookup = true }
            TextField("Flight number, e.g. BA178", text: $draft.flight.number).focused($focused)
                .accessibilityIdentifier("flight-number")
                #if os(iOS)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                #endif
            TextField("Airline (optional)", text: $draft.flight.airline).focused($focused)
            TextField("From airport, e.g. JFK", text: $draft.flight.departureAirport).focused($focused)
                #if os(iOS)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                #endif
            TextField("To airport, e.g. LHR", text: $draft.flight.arrivalAirport).focused($focused)
                #if os(iOS)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                #endif
            TextField("Booking reference (optional)", text: $draft.flight.bookingReference).focused($focused)
        } header: { Text("Flight") } footer: {
            Text("Look up a schedule or enter the details yourself. Review the details before saving.")
        }
    }

    private func save() {
        focused = false
        Task {
            do {
                try await store.saveItem(draft.input(), id: itemID, tripID: trip.id)
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
