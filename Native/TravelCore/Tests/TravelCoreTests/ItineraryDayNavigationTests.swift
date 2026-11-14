import Foundation
import Testing
@testable import TravelCore

struct ItineraryDayNavigationTests {
    @Test func selectingADayShowsItsStopsButCountsEachPlanOnce() throws {
        let train = item("train", .init(kind: .transport, title: "Train", start: day("2027-03-04"), end: day("2027-03-04"),
            startTime: clock("09:00"), endTime: clock("10:30"), transport: .init()))
        let stay = item("stay", .init(kind: .lodging, title: "Hotel", start: day("2027-03-04"), end: day("2027-03-08")))
        let open = item("open", .init(kind: .activity, title: "Restaurant idea"))
        let items = [open, stay, train]
        let all = ItineraryDayNavigation(items: items)
        #expect(all.days.map(\.id) == ["2027-03-04", "2027-03-08", "undated"])
        #expect(all.visibleDays == ItineraryTimeline.days(for: items))
        #expect(all.totalPlans == 3 && all.visiblePlans == 3)
        #expect(all.previousID == nil && all.nextID == nil)
        let first = ItineraryDayNavigation(items: items, selectedID: "2027-03-04")
        #expect(first.visibleDays.count == 1 && first.visiblePlans == 2 && first.totalPlans == 3)
        #expect(first.visibleDays.flatMap(\.events).map(\.role) == [.departure, .arrival, .checkIn])
        #expect(Set(first.visibleDays.flatMap(\.events).map { $0.item.id }) == [train.id, stay.id])
        #expect(first.previousID == nil && first.nextID == "2027-03-08")
    }

    @Test func navigationSkipsEmptyDatesAndEndsWithUndatedPlans() {
        let stay = item("stay", .init(kind: .lodging, title: "Long stay", start: day("2027-03-04"), end: day("2028-03-04")))
        let open = item("open", .init(kind: .activity, title: "Choose a cafe"))
        let items = [stay, open]
        let checkout = ItineraryDayNavigation(items: items, selectedID: "2028-03-04")
        #expect(checkout.days.count == 3 && checkout.visiblePlans == 1)
        #expect(checkout.previousID == "2027-03-04" && checkout.nextID == "undated")
        #expect(checkout.visibleDays.flatMap(\.events).map(\.role) == [.checkOut])
        let undated = ItineraryDayNavigation(items: items, selectedID: "undated")
        #expect(undated.selectedDay?.day == nil && undated.selectedID == "undated")
        #expect(undated.visibleDays.flatMap(\.events).map { $0.item.id } == [open.id])
        #expect(undated.previousID == "2028-03-04" && undated.nextID == nil)
        let onlyUndated = ItineraryDayNavigation(items: [open], selectedID: "undated")
        #expect(onlyUndated.previousID == nil && onlyUndated.nextID == nil && onlyUndated.visiblePlans == 1)
    }

    @Test func dateLineAndOvernightJourneysKeepTheSamePlanOnEachLocalDay() throws {
        let flight = item("flight", try ItineraryInput(kind: .flight, title: "Pacific flight", flight: .init(number: "NZ8",
            departureLocal: LocalMoment(rawValue: "2027-03-05T09:30"), arrivalLocal: LocalMoment(rawValue: "2027-03-04T22:15"))).validated())
        let train = item("train", .init(kind: .transport, title: "Overnight train", start: day("2027-03-05"), end: day("2027-03-06"),
            startTime: clock("23:30"), endTime: clock("06:00"), transport: .init()))
        let items = [train, flight]
        let arrival = ItineraryDayNavigation(items: items, selectedID: "2027-03-04")
        #expect(arrival.visibleDays.flatMap(\.events).map(\.role) == [.arrival])
        #expect(arrival.visibleDays[0].events[0].item == flight)
        let departure = ItineraryDayNavigation(items: items, selectedID: "2027-03-05")
        #expect(departure.visiblePlans == 2 && departure.totalPlans == 2)
        #expect(departure.nextID == "2027-03-06")
        let overnightArrival = ItineraryDayNavigation(items: items, selectedID: "2027-03-06")
        #expect(overnightArrival.visibleDays[0].events[0].item == train)
        #expect(overnightArrival.visibleDays[0].events[0].time == clock("06:00"))
    }

    @Test func movedOrRemovedDaysFallBackToAllAndEmptyTripsStayEmpty() {
        let first = item("a", .init(kind: .activity, title: "Museum", start: day("2027-03-04")))
        let second = item("b", .init(kind: .activity, title: "Tour", start: day("2027-03-08")))
        let selected = ItineraryDayNavigation(items: [first, second], selectedID: "2027-03-04")
        #expect(selected.visiblePlans == 1)
        var edited = first.input
        edited.start = day("2027-03-08")
        let moved = item(first.id, edited)
        let refreshed = ItineraryDayNavigation(items: [moved, second], selectedID: selected.selectedID)
        #expect(refreshed.selectedID == nil && refreshed.visiblePlans == 2)
        let stillExists = ItineraryDayNavigation(items: [moved, second], selectedID: "2027-03-08")
        #expect(stillExists.selectedID == "2027-03-08" && stillExists.visiblePlans == 2)
        let removed = ItineraryDayNavigation(items: [second], selectedID: selected.selectedID)
        #expect(removed.selectedID == nil && removed.visiblePlans == 1)
        let empty = ItineraryDayNavigation(items: [], selectedID: "undated")
        #expect(empty.days.isEmpty && empty.visibleDays.isEmpty && empty.selectedID == nil)
        #expect(empty.totalPlans == 0 && empty.visiblePlans == 0 && empty.nextID == nil && empty.previousID == nil)
    }

    private func day(_ text: String) -> TravelDay { TravelDay(rawValue: text)! }
    private func clock(_ text: String) -> LocalClock { LocalClock(rawValue: text)! }
    private func item(_ id: String, _ input: ItineraryInput) -> ItineraryItem {
        ItineraryItem(id: id, tripID: "trip", input: input, createdAt: Date(timeIntervalSince1970: 1_700_000_000))
    }
}
