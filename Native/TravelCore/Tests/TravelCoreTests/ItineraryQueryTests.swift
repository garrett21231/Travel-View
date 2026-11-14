import Foundation
import Testing
@testable import TravelCore

struct ItineraryQueryTests {
    @Test func emptyQueriesKeepTheExistingStableDateAndTimeOrder() {
        let early = item("a", ItineraryInput(kind: .activity, title: "Early", start: day("2027-03-04"), startTime: clock("09:00")))
        let later = item("b", ItineraryInput(kind: .activity, title: "Later", start: day("2027-03-04"), startTime: clock("12:00")))
        let unknownTime = item("c", ItineraryInput(kind: .activity, title: "Open time", start: day("2027-03-04")))
        let undated = item("d", ItineraryInput(kind: .activity, title: "Open date"))
        let input = [undated, unknownTime, later, early]
        #expect(ItineraryQuery().matching(input) == [early, later, unknownTime, undated])
        let whitespace = ItineraryQuery(text: "  \n \t ")
        #expect(!whitespace.isActive)
        #expect(whitespace.matching(input) == ItineraryQuery().matching(input.reversed()))
    }

    @Test func textTypeStateAndUndatedFiltersAllApplyTogether() {
        let wanted = item("a", ItineraryInput(kind: .lodging, title: "Riverside hotel", location: "London", bookingState: .idea))
        let booked = item("b", ItineraryInput(kind: .lodging, title: "Riverside hotel", location: "London", bookingState: .booked))
        let dated = item("c", ItineraryInput(kind: .lodging, title: "Riverside hotel", start: day("2027-03-04"), location: "London", bookingState: .idea))
        let wrongKind = item("d", ItineraryInput(kind: .activity, title: "Riverside walk", location: "London", bookingState: .idea))
        let query = ItineraryQuery(text: " LONDON\nriver ", kind: .lodging, bookingState: .idea, undatedOnly: true)
        #expect(query.isActive)
        #expect(query.matching([wanted, booked, dated, wrongKind]) == [wanted])
        #expect(ItineraryQuery(text: "London missing", kind: .lodging).matching([wanted]).isEmpty)
        #expect(ItineraryQuery(bookingState: .planned).matching([wanted, booked]).isEmpty)
    }

    @Test func searchesTitlesLocationsNotesReferencesAndCurrentFlightDetails() {
        let flight = item("flight", ItineraryInput(kind: .flight, title: "London flight", notes: "Request aisle seat",
                          flight: FlightDetails(number: "BA178", airline: "British Airways", departureAirport: "JFK", arrivalAirport: "LHR", bookingReference: "FLIGHT-42")))
        let cafe = item("cafe", ItineraryInput(kind: .activity, title: "Café lunch", location: "South Bank", notes: "Meet at entrance", reservationReference: "TABLE-27"))
        let hotel = item("hotel", ItineraryInput(kind: .lodging, title: "Hotel", reservationReference: "HOTEL-4821"))
        let all = [flight, cafe, hotel]
        for text in ["ba 178", "airways", "jfk lhr", "FLIGHT-42", "aisle"] {
            #expect(ItineraryQuery(text: text).matching(all) == [flight])
        }
        for text in ["CAFE", "bank lunch", "entrance", "table-27"] {
            #expect(ItineraryQuery(text: text).matching(all) == [cafe])
        }
        #expect(ItineraryQuery(text: "hotel-4821").matching(all) == [hotel])
        #expect(ItineraryQuery(text: "FLIGHT-42", kind: .lodging).matching(all).isEmpty)
    }

    @Test func lookupSnapshotsDoNotMakeOutdatedProviderFieldsSearchable() {
        let snapshot = FlightSchedule(number: "BA178", airline: "Old Airline",
                                      departure: FlightStop(airport: "JFK", local: nil, timeZone: nil),
                                      arrival: FlightStop(airport: "LHR", local: nil, timeZone: nil),
                                      status: "Cancelled", provider: "Sample provider", fetchedAt: .now)
        let flight = item("flight", ItineraryInput(kind: .flight, title: "My flight",
                          flight: FlightDetails(number: "BA178", airline: "New Airline", departureAirport: "EWR", arrivalAirport: "LGW", lastLookup: snapshot)))
        for text in ["Old", "JFK", "LHR", "Cancelled", "provider"] {
            #expect(ItineraryQuery(text: text).matching([flight]).isEmpty)
        }
        #expect(ItineraryQuery(text: "new ewr lgw").matching([flight]) == [flight])
    }

    @Test func summariesCountWholePlansAndUserChosenStates() throws {
        let flight = item("flight", try ItineraryInput(kind: .flight, title: "Flight",
                          flight: FlightDetails(number: "BA178", departureLocal: LocalMoment(rawValue: "2027-03-04T19:30"),
                                                arrivalLocal: LocalMoment(rawValue: "2027-03-05T07:20")), bookingState: .booked).validated())
        let stay = item("stay", ItineraryInput(kind: .lodging, title: "Stay", start: day("2027-03-05"), end: day("2027-03-08"), bookingState: .planned))
        let idea = item("idea", ItineraryInput(kind: .activity, title: "Tour idea", bookingState: .idea, reservationReference: "REF-DOES-NOT-MEAN-BOOKED"))
        let plans = [flight, stay, idea]
        #expect(ItineraryTimeline.days(for: plans).flatMap(\.events).count == 5)
        let summary = ItinerarySummary(items: plans)
        #expect(summary.total == 3)
        #expect(summary.flights == 1 && summary.stays == 1 && summary.activities == 1)
        #expect(summary.ideas == 1 && summary.planned == 1 && summary.booked == 1)
        #expect(summary.undated == 1)
        let empty = ItinerarySummary(items: [])
        #expect(empty.total == 0 && empty.booked == 0 && empty.undated == 0)
        #expect(ItineraryQuery().matching([]).isEmpty)
    }

    @Test func undatedMeansNeitherStartNorEndIsSaved() {
        let open = item("open", ItineraryInput(kind: .activity, title: "Open"))
        let partial = item("partial", ItineraryInput(kind: .flight, title: "Arrival only", end: day("2027-03-05"), flight: FlightDetails(number: "BA178")))
        let dated = item("dated", ItineraryInput(kind: .activity, title: "Open time", start: day("2027-03-05")))
        #expect(ItineraryQuery(undatedOnly: true).matching([open, partial, dated]) == [open])
        #expect(ItinerarySummary(items: [open, partial, dated]).undated == 1)
    }

    private func item(_ id: String, _ input: ItineraryInput) -> ItineraryItem {
        ItineraryItem(id: id, tripID: "trip", input: input, createdAt: Date(timeIntervalSince1970: 1_700_000_000))
    }
    private func day(_ raw: String) -> TravelDay { TravelDay(rawValue: raw)! }
    private func clock(_ raw: String) -> LocalClock { LocalClock(rawValue: raw)! }
}
