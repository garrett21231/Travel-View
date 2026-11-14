import Foundation
import GRDB

public enum ItineraryKind: String, Codable, CaseIterable, Identifiable, Sendable, DatabaseValueConvertible {
    case flight, lodging, activity
    public var id: Self { self }
    public var title: String { rawValue.capitalized }
    public var symbol: String {
        switch self { case .flight: "airplane"; case .lodging: "bed.double"; case .activity: "map" }
    }
}

/// User-owned flight details stay independent from the last provider response.
public struct FlightDetails: Codable, Equatable, Sendable {
    public var number: String
    public var airline: String
    public var departureAirport: String
    public var arrivalAirport: String
    public var departureLocal: LocalMoment?
    public var arrivalLocal: LocalMoment?
    public var bookingReference: String
    public var lastLookup: FlightSchedule?

    public init(number: String = "", airline: String = "", departureAirport: String = "", arrivalAirport: String = "",
                departureLocal: LocalMoment? = nil, arrivalLocal: LocalMoment? = nil,
                bookingReference: String = "", lastLookup: FlightSchedule? = nil) {
        self.number = number; self.airline = airline
        self.departureAirport = departureAirport; self.arrivalAirport = arrivalAirport
        self.departureLocal = departureLocal; self.arrivalLocal = arrivalLocal
        self.bookingReference = bookingReference; self.lastLookup = lastLookup
    }

    public init(schedule: FlightSchedule) {
        self.init(number: schedule.number, airline: schedule.airline,
                  departureAirport: schedule.departure.airport, arrivalAirport: schedule.arrival.airport,
                  departureLocal: schedule.departure.local, arrivalLocal: schedule.arrival.local, lastLookup: schedule)
    }

    func validated() throws -> Self {
        var value = self
        value.number = try FlightQuery.normalizedNumber(number)
        value.airline = airline.trimmingCharacters(in: .whitespacesAndNewlines)
        value.departureAirport = departureAirport.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        value.arrivalAirport = arrivalAirport.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        value.bookingReference = bookingReference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard [value.departureAirport, value.arrivalAirport].allSatisfy({
            $0.isEmpty || $0.range(of: #"^[A-Z0-9]{3,4}$"#, options: .regularExpression) != nil
        }) else { throw TripError("Use a 3–4 character airport code, such as JFK or EGLL.") }
        guard value.airline.count <= 160, value.bookingReference.count <= 80 else {
            throw TripError("Keep the airline within 160 characters and the booking reference within 80.")
        }
        if let snapshot = lastLookup { try snapshot.validate() }
        return value
    }
}

public struct ItineraryInput: Equatable, Sendable {
    public var kind: ItineraryKind
    public var title: String
    public var start: TravelDay?
    public var end: TravelDay?
    public var location: String
    public var notes: String
    public var flight: FlightDetails?
    public var startTime: LocalClock?
    public var endTime: LocalClock?
    public var bookingState: BookingState
    public var reservationReference: String

    public init(kind: ItineraryKind, title: String, start: TravelDay? = nil, end: TravelDay? = nil,
                location: String = "", notes: String = "", flight: FlightDetails? = nil,
                startTime: LocalClock? = nil, endTime: LocalClock? = nil,
                bookingState: BookingState = .planned, reservationReference: String = "") {
        self.kind = kind; self.title = title; self.start = start; self.end = end
        self.location = location; self.notes = notes; self.flight = flight
        self.startTime = startTime; self.endTime = endTime
        self.bookingState = bookingState; self.reservationReference = reservationReference
    }

    public func validated() throws -> Self {
        var value = self
        value.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        value.location = location.trimmingCharacters(in: .whitespacesAndNewlines)
        value.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        // Flight references retain their existing home in FlightDetails for archive compatibility.
        value.reservationReference = kind == .flight ? "" : reservationReference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.title.isEmpty, value.title.count <= 160 else { throw TripError("Enter a title of up to 160 characters.") }
        guard value.location.count <= 300, value.notes.count <= 4000 else {
            throw TripError("Use up to 300 characters for the location and 4,000 for notes.")
        }
        guard value.reservationReference.count <= 80 else {
            throw TripError("Keep the confirmation reference within 80 characters.")
        }
        if kind == .flight {
            guard let flight else { throw TripError("Add the flight details.") }
            value.flight = try flight.validated()
            value.start = flight.departureLocal?.day ?? start
            value.end = flight.arrivalLocal?.day ?? end
            value.startTime = nil
            value.endTime = nil
            // A date-line crossing can arrive on the previous local day.
        } else {
            value.flight = nil
            guard end == nil || (start != nil && end! >= start!) else {
                throw TripError("Choose an end date on or after the start date.")
            }
            guard startTime == nil || start != nil, endTime == nil || end != nil else {
                throw TripError("Choose a date before adding its time.")
            }
            if let start, start == end, let startTime, let endTime, endTime < startTime {
                throw TripError("Choose an end time on or after the start time, or move the end to a later day.")
            }
        }
        return value
    }
}

/// Stable IDs let later expenses and traveler participation refer to an itinerary item.
public struct ItineraryItem: Identifiable, Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "itineraryItems"
    public let id: String
    public let tripID: String
    public let kind: ItineraryKind
    public let title: String
    public let start: TravelDay?
    public let end: TravelDay?
    public let location: String
    public let notes: String
    public let flight: FlightDetails?
    public let startTime: LocalClock?
    public let endTime: LocalClock?
    public let bookingState: BookingState
    public let reservationReference: String
    public let createdAt: Date

    init(id: String, tripID: String, input: ItineraryInput, createdAt: Date) {
        self.id = id; self.tripID = tripID; kind = input.kind; title = input.title
        start = input.start; end = input.end; location = input.location; notes = input.notes
        flight = input.flight; self.createdAt = createdAt
        startTime = input.startTime; endTime = input.endTime
        bookingState = input.bookingState; reservationReference = input.reservationReference
    }
    public var input: ItineraryInput {
        ItineraryInput(kind: kind, title: title, start: start, end: end, location: location, notes: notes,
                       flight: flight, startTime: startTime, endTime: endTime,
                       bookingState: bookingState, reservationReference: reservationReference)
    }
    public var confirmationReference: String { kind == .flight ? flight?.bookingReference ?? "" : reservationReference }
    public var mapsURL: URL? { LocationLink.mapsSearch(for: location) }

    private enum CodingKeys: String, CodingKey {
        case id, tripID, kind, title, start, end, location, notes, flight, startTime, endTime, bookingState, reservationReference, createdAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        tripID = try values.decode(String.self, forKey: .tripID)
        kind = try values.decode(ItineraryKind.self, forKey: .kind)
        title = try values.decode(String.self, forKey: .title)
        start = try values.decodeIfPresent(TravelDay.self, forKey: .start)
        end = try values.decodeIfPresent(TravelDay.self, forKey: .end)
        location = try values.decode(String.self, forKey: .location)
        notes = try values.decode(String.self, forKey: .notes)
        flight = try values.decodeIfPresent(FlightDetails.self, forKey: .flight)
        startTime = try values.decodeIfPresent(LocalClock.self, forKey: .startTime)
        endTime = try values.decodeIfPresent(LocalClock.self, forKey: .endTime)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        // Native backups made before version 4 have neither field. Never infer Booked from a reference.
        bookingState = values.contains(.bookingState) ? try values.decode(BookingState.self, forKey: .bookingState) : .planned
        reservationReference = values.contains(.reservationReference) ? try values.decode(String.self, forKey: .reservationReference) : ""
    }
    public var dateText: String {
        guard let start else { return "Date to be decided" }
        if let end, end != start { return "\(start.formatted) – \(end.formatted)" }
        return start.formatted
    }
    public static func ordered(_ items: [Self]) -> [Self] {
        items.sorted {
            if $0.start != $1.start {
                guard let left = $0.start else { return false }
                guard let right = $1.start else { return true }
                return left < right
            }
            let leftClock = $0.flight?.departureLocal?.clock ?? $0.startTime?.rawValue ?? "99:99"
            let rightClock = $1.flight?.departureLocal?.clock ?? $1.startTime?.rawValue ?? "99:99"
            return (leftClock, $0.createdAt, $0.id) < (rightClock, $1.createdAt, $1.id)
        }
    }
}
