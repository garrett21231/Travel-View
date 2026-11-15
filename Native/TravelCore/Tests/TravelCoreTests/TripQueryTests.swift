import Foundation
import Testing
@testable import TravelCore

struct TripQueryTests {
    @Test func searchesNamesAndDestinationsAcrossWordsCaseAndAccents() {
        let canada = trip("a", "Autumn escape", destinations: ["Montréal", "Québec City"], notes: "Hidden notes phrase")
        let france = trip("b", "Paris weekend", destinations: ["Paris"])
        let open = trip("c", "Open plan")
        let trips = [open, france, canada]
        for text in ["MONTREAL", "quebec autumn", " city\n montreal ", "escape"] {
            #expect(TripQuery(text: text).matching(trips) == [canada])
        }
        #expect(TripQuery(text: "Paris").matching(trips) == [france])
        #expect(TripQuery(text: "Hidden notes phrase").matching(trips).isEmpty)
        #expect(TripQuery(text: "Destination undecided").matching(trips).isEmpty)
        #expect(TripQuery(text: " ").isSearching == false)
        #expect(TripQuery(text: "Montréal").isSearching)
        #expect(TripQuery(text: " \n\t ", sortOrder: .newest).matching(trips) == TripQuery(sortOrder: .newest).matching(trips))
        #expect(TripQuery(text: "Paris").matching([]).isEmpty)
    }

    @Test func departureSortIncludesPastDatesAndKeepsUndatedTripsLastWithStableTies() {
        let past = trip("past", "Past", start: "2020-01-01")
        let early = trip("a", "Early", start: "2027-01-01", created: 100)
        let tied = trip("b", "Same departure", start: "2027-01-01", created: 100)
        let laterCreation = trip("c", "Created later", start: "2027-01-01", created: 200)
        let laterDeparture = trip("later", "Later", start: "2027-02-01")
        let open = trip("open", "Undated", created: 1)
        let trips = [open, laterDeparture, laterCreation, tied, early, past]
        let expected = [past, early, tied, laterCreation, laterDeparture, open]
        #expect(TripQuery(sortOrder: .departure).matching(trips) == expected)
        #expect(TripQuery(sortOrder: .departure).matching(Array(trips.reversed())) == expected)
        #expect(Trip.upcoming(trips, on: day("2026-11-14")) == Array(expected.dropFirst()))
    }

    @Test func newestSortUsesCreationTimeAndDeterministicIdentityTies() {
        let oldest = trip("old", "Oldest", created: 1)
        let first = trip("a", "New A", created: 300)
        let second = trip("b", "New B", created: 300)
        let trips = [first, oldest, second]
        #expect(TripQuery(sortOrder: .newest).matching(trips) == [second, first, oldest])
        #expect(TripQuery(sortOrder: .newest).matching(Array(trips.reversed())) == [second, first, oldest])
    }

    @Test func nameSortIgnoresCaseAndAccentsAndOrdersNumbersNaturally() {
        let first = trip("a", "Málaga")
        let second = trip("b", "malaga")
        let two = trip("c", "Paris 2")
        let ten = trip("d", "Paris 10")
        let expected = [first, second, two, ten]
        #expect(TripQuery(sortOrder: .name).matching(Array(expected.reversed())) == expected)
        #expect(TripQuery(text: "paris", sortOrder: .name).matching(Array(expected.reversed())) == [two, ten])
    }

    @Test func searchingUpcomingAndAllTripsRespectsCompletedOngoingAndOpenPlans() {
        let past = trip("past", "Lisbon memories", destinations: ["Lisbon"], start: "2020-01-01")
        let active = trip("active", "City break", destinations: ["Lisbon"], start: "2026-11-10", end: "2026-11-16")
        let future = trip("future", "Next visit", destinations: ["Lisbon"], start: "2027-04-01")
        let open = trip("open", "Lisbon someday")
        let other = trip("other", "Rome", destinations: ["Rome"], start: "2027-04-01")
        let all = [past, active, future, open, other]
        let query = TripQuery(text: "lisbon", sortOrder: .departure)
        #expect(query.matching(all) == [past, active, future, open])
        #expect(query.matching(Trip.upcoming(all, on: day("2026-11-14"))) == [active, future, open])
    }

    @Test func savedEditsAreMatchedAgainstCurrentNamesAndDestinations() {
        let original = trip("a", "Weekend", destinations: ["Paris"])
        let query = TripQuery(text: "Paris")
        #expect(query.matching([original]) == [original])
        var input = original.input
        input.name = "Italian weekend"; input.destinations = ["Rome"]
        let edited = Trip(id: original.id, input: input, createdAt: original.createdAt)
        #expect(query.matching([edited]).isEmpty)
        #expect(TripQuery(text: "italian rome").matching([edited]) == [edited])
        #expect(original.destinations == ["Paris"])
    }

    private func day(_ value: String) -> TravelDay { TravelDay(rawValue: value)! }
    private func trip(_ id: String, _ name: String, destinations: [String] = [], notes: String = "",
                      start: String? = nil, end: String? = nil, created: TimeInterval = 100) -> Trip {
        Trip(id: id, input: TripInput(name: name, destinations: destinations,
                                     start: start.map(day), end: (end ?? start).map(day), notes: notes),
             createdAt: Date(timeIntervalSince1970: created))
    }
}
