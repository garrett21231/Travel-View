import Foundation

/// Searches saved records, rather than day entries, so a flight or stay appears only once.
public struct ItineraryQuery: Hashable, Sendable {
    public var text: String
    public var kind: ItineraryKind?
    public var bookingState: BookingState?
    public var undatedOnly: Bool

    public init(text: String = "", kind: ItineraryKind? = nil, bookingState: BookingState? = nil, undatedOnly: Bool = false) {
        self.text = text; self.kind = kind; self.bookingState = bookingState; self.undatedOnly = undatedOnly
    }

    public var isActive: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || kind != nil || bookingState != nil || undatedOnly
    }

    public func matching(_ items: [ItineraryItem]) -> [ItineraryItem] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let matches = items.filter { item in
            guard kind == nil || item.kind == kind,
                  bookingState == nil || item.bookingState == bookingState,
                  !undatedOnly || (item.start == nil && item.end == nil) else { return false }
            let flight = item.flight
            let fields = [item.title, item.location, item.notes, item.confirmationReference,
                          flight?.number ?? "", flight?.airline ?? "", flight?.departureAirport ?? "", flight?.arrivalAirport ?? ""]
            // Each word must match a field; words may be in a different order or different fields.
            // Do not search the old provider snapshot: results describe the user's current saved plan.
            return words.allSatisfy { word in
                fields.contains { $0.range(of: word, options: [.caseInsensitive, .diacriticInsensitive],
                                            locale: Locale(identifier: "en_US_POSIX")) != nil }
            }
        }
        return ItineraryItem.ordered(matches)
    }
}

/// Counts whole plans. Departure/arrival and check-in/out never increase the totals.
public struct ItinerarySummary: Equatable, Sendable {
    public let total: Int
    public let flights: Int
    public let stays: Int
    public let activities: Int
    public let ideas: Int
    public let planned: Int
    public let booked: Int
    public let undated: Int

    public init(items: [ItineraryItem]) {
        total = items.count
        flights = items.filter { $0.kind == .flight }.count
        stays = items.filter { $0.kind == .lodging }.count
        activities = items.filter { $0.kind == .activity }.count
        ideas = items.filter { $0.bookingState == .idea }.count
        planned = items.filter { $0.bookingState == .planned }.count
        booked = items.filter { $0.bookingState == .booked }.count
        undated = items.filter { $0.start == nil && $0.end == nil }.count
    }
}
