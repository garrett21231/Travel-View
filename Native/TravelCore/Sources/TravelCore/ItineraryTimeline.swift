import Foundation

/// Calendar entries are projections of an item. Both ends of a journey still edit the same saved record.
public struct ItineraryEvent: Identifiable, Equatable, Sendable {
    public enum Role: String, Sendable {
        case plan, departure, arrival, checkIn, checkOut, activity, activityEnd
        public var title: String {
            switch self {
            case .plan: "Plan"
            case .departure: "Departure"
            case .arrival: "Arrival"
            case .checkIn: "Check-in"
            case .checkOut: "Check-out"
            case .activity: "Activity"
            case .activityEnd: "Activity ends"
            }
        }
    }
    public let item: ItineraryItem
    public let role: Role
    public let day: TravelDay?
    public let time: LocalClock?
    public var id: String { item.id + "/" + role.rawValue }
    public var title: String { role == .plan ? item.kind.title : role.title }
    public var timeText: String {
        if role == .activity, item.start == item.end, let end = item.endTime {
            if let time { return time == end ? time.rawValue : "\(time.rawValue)–\(end.rawValue)" }
            return "Until \(end.rawValue)"
        }
        return time?.rawValue ?? "Time to be decided"
    }
}

public struct ItineraryDay: Identifiable, Equatable, Sendable {
    public let day: TravelDay?
    public let events: [ItineraryEvent]
    public var id: String { day?.rawValue ?? "undated" }
}

public enum ItineraryTimeline {
    /// Only actual dates generate groups. A long stay creates check-in/out entries, not thousands of empty days.
    public static func days(for items: [ItineraryItem]) -> [ItineraryDay] {
        let events = items.flatMap(events(for:))
        let dated = Dictionary(grouping: events.compactMap { event -> ItineraryEvent? in event.day == nil ? nil : event }, by: { $0.day! })
        var days = dated.keys.sorted().map { ItineraryDay(day: $0, events: ordered(dated[$0]!)) }
        let undated = ordered(events.filter { $0.day == nil })
        if !undated.isEmpty { days.append(ItineraryDay(day: nil, events: undated)) }
        return days
    }

    /// This is the next calendar day with plans, not a live countdown across unknown time zones.
    public static func upcomingDay(in days: [ItineraryDay], on today: TravelDay) -> ItineraryDay? {
        days.first { $0.day.map { $0 >= today } ?? false }
    }

    private static func ordered(_ events: [ItineraryEvent]) -> [ItineraryEvent] {
        events.sorted {
            let left = $0.time?.rawValue ?? "99:99"
            let right = $1.time?.rawValue ?? "99:99"
            if left != right { return left < right }
            // Creation order and IDs make ties stable across database loads and backup restores.
            return ($0.item.createdAt, $0.item.id, rank($0.role)) < ($1.item.createdAt, $1.item.id, rank($1.role))
        }
    }

    private static func rank(_ role: ItineraryEvent.Role) -> Int {
        switch role {
        case .plan, .departure, .checkIn, .activity: 0
        case .arrival, .checkOut, .activityEnd: 1
        }
    }

    private static func events(for item: ItineraryItem) -> [ItineraryEvent] {
        func event(_ role: ItineraryEvent.Role, _ day: TravelDay?, _ time: LocalClock?) -> ItineraryEvent {
            ItineraryEvent(item: item, role: role, day: day, time: time)
        }
        guard item.start != nil || item.end != nil else { return [event(.plan, nil, nil)] }
        switch item.kind {
        case .flight:
            let departure = item.flight?.departureLocal.flatMap { LocalClock(rawValue: $0.clock) }
            let arrival = item.flight?.arrivalLocal.flatMap { LocalClock(rawValue: $0.clock) }
            var entries = [event(.departure, item.start, departure)]
            if let end = item.end { entries.append(event(.arrival, end, arrival)) }
            return entries
        case .lodging:
            var entries = [event(.checkIn, item.start, item.startTime)]
            if let end = item.end { entries.append(event(.checkOut, end, item.endTime)) }
            return entries
        case .transport:
            var entries = [event(.departure, item.start, item.startTime)]
            if let end = item.end { entries.append(event(.arrival, end, item.endTime)) }
            return entries
        case .activity:
            var entries = [event(.activity, item.start, item.startTime)]
            if let end = item.end, end != item.start { entries.append(event(.activityEnd, end, item.endTime)) }
            return entries
        }
    }
}
