import Foundation

public enum TripSortOrder: String, CaseIterable, Identifiable, Sendable {
    case departure, newest, name
    public var id: Self { self }
    public var title: String {
        switch self {
        case .departure: "Departure date"
        case .newest: "Newest first"
        case .name: "Name (A–Z)"
        }
    }

    func ordered(_ trips: [Trip]) -> [Trip] {
        switch self {
        case .departure:
            return trips.sorted { left, right in
                if left.start != right.start {
                    guard let start = left.start else { return false }
                    guard let other = right.start else { return true }
                    return start < other
                }
                return (left.createdAt, left.id) < (right.createdAt, right.id)
            }
        case .newest:
            return trips.sorted { ($0.createdAt, $0.id) > ($1.createdAt, $1.id) }
        case .name:
            let locale = Locale(identifier: "en_US_POSIX")
            // Fold once per name so capitalization and accents cannot split the alphabetical groups.
            return trips.map { (trip: $0, name: $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)) }
                .sorted {
                    let comparison = $0.name.compare($1.name, options: .numeric, locale: locale)
                    return comparison == .orderedSame ? $0.trip.id < $1.trip.id : comparison == .orderedAscending
                }.map(\.trip)
        }
    }
}

/// The caller supplies Upcoming or All trips. Searching changes only the visible collection.
public struct TripQuery: Equatable, Sendable {
    public var text: String
    public var sortOrder: TripSortOrder
    public init(text: String = "", sortOrder: TripSortOrder = .departure) {
        self.text = text; self.sortOrder = sortOrder
    }

    public var isSearching: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    public func matching(_ trips: [Trip]) -> [Trip] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        return sortOrder.ordered(trips.filter { trip in
            // Every word must match a name or destination; notes and private plan details are outside this search.
            let fields = [trip.name] + trip.destinations
            return words.allSatisfy { word in
                fields.contains { $0.range(of: word, options: [.caseInsensitive, .diacriticInsensitive],
                                           locale: Locale(identifier: "en_US_POSIX")) != nil }
            }
        })
    }
}
