import Foundation

/// A view of the existing timeline, not another set of saved plans.
/// A missing selection means all days; a removed day falls back to all days too.
public struct ItineraryDayNavigation: Sendable {
    public let days: [ItineraryDay]
    public let selectedID: String?
    public let totalPlans: Int

    public init(items: [ItineraryItem], selectedID: String? = nil) {
        days = ItineraryTimeline.days(for: items)
        self.selectedID = days.contains { $0.id == selectedID } ? selectedID : nil
        totalPlans = Set(items.map(\.id)).count
    }

    public var selectedDay: ItineraryDay? { days.first { $0.id == selectedID } }
    public var visibleDays: [ItineraryDay] { selectedDay.map { [$0] } ?? days }
    public var visiblePlans: Int { Set(visibleDays.flatMap(\.events).map { $0.item.id }).count }

    public var previousID: String? {
        guard let index = days.firstIndex(where: { $0.id == selectedID }), index > 0 else { return nil }
        return days[index - 1].id
    }

    public var nextID: String? {
        guard let index = days.firstIndex(where: { $0.id == selectedID }), index + 1 < days.count else { return nil }
        return days[index + 1].id
    }
}
