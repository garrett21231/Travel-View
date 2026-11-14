import Foundation

/// Notes and references are opt-in for each preview. These choices never change saved plans.
public struct ItineraryTextOptions: Equatable, Sendable {
    public var includeNotes: Bool
    public var includeReferences: Bool

    public init(includeNotes: Bool = false, includeReferences: Bool = false) {
        self.includeNotes = includeNotes; self.includeReferences = includeReferences
    }
}

/// A readable copy, separate from the JSON backup used to restore app records.
public enum ItineraryText {
    public static func make(trip: Trip, items: [ItineraryItem], options: ItineraryTextOptions = .init()) -> String {
        // Scope here as well as in the UI, so callers cannot include another trip's records by accident.
        let days = ItineraryTimeline.days(for: items.filter { $0.tripID == trip.id })
        var lines = ["Travel View itinerary", trip.name, "Destinations: \(trip.destinationText)", "Dates: \(trip.dateText)", "",
                     "Times are local to each location. Flight times are local to each airport.",
                     "Booking states are labels chosen for these plans."]
        if options.includeNotes, !trip.notes.isEmpty {
            lines += ["", "Trip notes:", indented(trip.notes)]
        }
        if days.isEmpty {
            lines += ["", "No itinerary items yet."]
        }
        var detailedIDs: Set<String> = []
        for day in days {
            lines += ["", day.day?.formatted ?? "Undated plans"]
            for event in day.events {
                let item = event.item
                lines.append("- \(event.timeText) — \(event.title): \(item.title)")
                lines.append("  Booking state: \(item.bookingState.title)")
                if let flight = item.flight {
                    lines.append("  Flight: \(flight.number)\(flight.airline.isEmpty ? "" : " · " + flight.airline)")
                    lines.append("  Route: \(airport(flight.departureAirport)) → \(airport(flight.arrivalAirport))")
                }
                if !item.location.isEmpty { lines.append("  Location: \(item.location)") }
                if let transport = item.transport {
                    lines.append("  Transport: \(transport.mode.title)\(transport.operatorName.isEmpty ? "" : " · " + transport.operatorName)")
                    lines.append("  Route: \(transport.routeText)")
                }
                // Both ends of a journey/stay remain visible. Longer personal details appear once per item.
                if detailedIDs.insert(item.id).inserted {
                    if options.includeReferences, !item.confirmationReference.isEmpty {
                        lines.append("  \(item.kind == .flight ? "Booking reference" : "Confirmation reference"): \(item.confirmationReference)")
                    }
                    if options.includeNotes, !item.notes.isEmpty {
                        lines += ["  Notes:", indented(item.notes, spaces: 4)]
                    }
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func airport(_ code: String) -> String { code.isEmpty ? "Airport to be decided" : code }
    private static func indented(_ text: String, spaces: Int = 2) -> String {
        text.components(separatedBy: .newlines).map { String(repeating: " ", count: spaces) + $0 }.joined(separator: "\n")
    }
}
