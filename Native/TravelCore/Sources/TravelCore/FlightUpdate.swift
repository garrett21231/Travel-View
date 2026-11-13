import Foundation

/// Compare the saved plan, its original lookup, and a new schedule before changing anything.
public struct FlightUpdate: Sendable {
    public enum Field: String, CaseIterable, Identifiable, Sendable {
        case airline, departureAirport, arrivalAirport, departureTime, arrivalTime
        public var id: Self { self }
        public var title: String {
            switch self {
            case .airline: "Airline"
            case .departureAirport: "Departure airport"
            case .arrivalAirport: "Arrival airport"
            case .departureTime: "Departure date and time"
            case .arrivalTime: "Arrival date and time"
            }
        }
    }

    public struct Change: Identifiable, Sendable {
        public let field: Field
        public let saved: String
        public let latest: String
        public let differsFromLookup: Bool
        public let selectedByDefault: Bool
        public var id: Field { field }
    }

    public let base: ItineraryItem
    public let schedule: FlightSchedule
    public let changes: [Change]
    public let hasComparableLookup: Bool
    public var defaultSelection: Set<Field> { Set(changes.filter(\.selectedByDefault).map(\.field)) }

    public init(item: ItineraryItem, schedule: FlightSchedule) throws {
        guard item.kind == .flight, let plan = item.flight, let day = item.start else {
            throw TripError("Add a departure date to the flight before checking for updates.")
        }
        try schedule.validate()
        let number = try FlightQuery.normalizedNumber(plan.number)
        guard try FlightQuery.normalizedNumber(schedule.number) == number,
              schedule.departure.local.map({ $0.day == day }) ?? true else {
            throw TripError("This schedule is for a different flight or departure date. Your saved flight is unchanged.")
        }
        base = item
        self.schedule = schedule

        // If the user changed the flight identity/date, the older lookup is no longer a safe baseline.
        let previous = plan.lastLookup
        hasComparableLookup = previous.map {
            (try? FlightQuery.normalizedNumber($0.number)) == number && $0.departure.local?.day == day
        } ?? false
        let comparable = hasComparableLookup
        changes = Field.allCases.compactMap { field in
            let saved = Self.value(field, in: plan)
            guard let latest = Self.value(field, in: schedule), latest != saved else { return nil }
            let original = previous.flatMap { Self.value(field, in: $0) }
            let edited = comparable && saved != original
            return Change(field: field, saved: Self.display(saved, field: field), latest: Self.display(latest, field: field),
                          differsFromLookup: edited, selectedByDefault: comparable && !edited)
        }
    }

    /// A missing provider value never clears a saved value. Personal fields are never copied from the provider.
    public func applying(_ selection: Set<Field>) throws -> ItineraryInput {
        guard selection.isSubset(of: Set(changes.map(\.field))), var plan = base.flight else {
            throw TripError("The selected changes are no longer available. Check the flight again.")
        }
        for field in selection {
            switch field {
            case .airline: plan.airline = schedule.airline.trimmingCharacters(in: .whitespacesAndNewlines)
            case .departureAirport: plan.departureAirport = schedule.departure.airport
            case .arrivalAirport: plan.arrivalAirport = schedule.arrival.airport
            case .departureTime: plan.departureLocal = schedule.departure.local
            case .arrivalTime: plan.arrivalLocal = schedule.arrival.local
            }
        }
        plan.lastLookup = schedule
        var input = base.input
        input.flight = plan
        return try input.validated()
    }

    private static func value(_ field: Field, in plan: FlightDetails) -> String? {
        switch field {
        case .airline: nonempty(plan.airline)
        case .departureAirport: nonempty(plan.departureAirport)
        case .arrivalAirport: nonempty(plan.arrivalAirport)
        case .departureTime: plan.departureLocal?.rawValue
        case .arrivalTime: plan.arrivalLocal?.rawValue
        }
    }
    private static func value(_ field: Field, in schedule: FlightSchedule) -> String? {
        switch field {
        case .airline: nonempty(schedule.airline)
        case .departureAirport: nonempty(schedule.departure.airport)
        case .arrivalAirport: nonempty(schedule.arrival.airport)
        case .departureTime: schedule.departure.local?.rawValue
        case .arrivalTime: schedule.arrival.local?.rawValue
        }
    }
    private static func nonempty(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
    private static func display(_ text: String?, field: Field) -> String {
        guard let text else { return "Not set" }
        if field == .departureTime || field == .arrivalTime { return LocalMoment(rawValue: text)?.formatted ?? text }
        return text
    }
}
