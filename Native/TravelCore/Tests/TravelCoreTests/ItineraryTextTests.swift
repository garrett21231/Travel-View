import Foundation
import Testing
@testable import TravelCore

struct ItineraryTextTests {
    @Test func notesAndReferencesAreIndependentOptInChoices() throws {
        let trip = trip(notes: "Private trip note")
        let flight = try item(trip, ItineraryInput(kind: .flight, title: "Outbound", notes: "Private seat note",
                              flight: FlightDetails(number: "BA178", bookingReference: "FLIGHT-SECRET")))
        let hotel = try item(trip, ItineraryInput(kind: .lodging, title: "Hotel", notes: "Private hotel note", reservationReference: "HOTEL-SECRET"))
        for includeNotes in [false, true] {
            for includeReferences in [false, true] {
                let text = ItineraryText.make(trip: trip, items: [flight, hotel],
                                             options: ItineraryTextOptions(includeNotes: includeNotes, includeReferences: includeReferences))
                #expect(text.contains("Private trip note") == includeNotes)
                #expect(text.contains("Private seat note") == includeNotes)
                #expect(text.contains("Private hotel note") == includeNotes)
                #expect(text.contains("FLIGHT-SECRET") == includeReferences)
                #expect(text.contains("HOTEL-SECRET") == includeReferences)
            }
        }
        let defaultText = ItineraryText.make(trip: trip, items: [flight, hotel])
        #expect(!defaultText.contains("SECRET") && !defaultText.contains("Private"))
        #expect(!defaultText.contains(Money.formatted(trip.budgetCents!)))
        #expect(!defaultText.contains("Travelers:"))
    }

    @Test func exportsOnlyTheRequestedTripEvenIfTheCallerPassesEveryItem() throws {
        let trip = trip(), other = self.trip()
        let own = try item(trip, ItineraryInput(kind: .activity, title: "Own plan"))
        let foreign = try item(other, ItineraryInput(kind: .activity, title: "Other trip plan", notes: "Other notes", reservationReference: "OTHER-REF"))
        let options = ItineraryTextOptions(includeNotes: true, includeReferences: true)
        let text = ItineraryText.make(trip: trip, items: [foreign, own], options: options)
        #expect(text.contains("Own plan"))
        #expect(!text.contains("Other trip plan") && !text.contains("Other notes") && !text.contains("OTHER-REF"))
        #expect(ItineraryText.make(trip: trip, items: [foreign]).contains("No itinerary items yet."))
    }

    @Test func localDayOrderAndBothEndsOfDateLineFlightsArePreserved() throws {
        let trip = trip()
        let flight = try item(trip, ItineraryInput(kind: .flight, title: "Pacific flight", flight: FlightDetails(number: "NZ8",
                              departureAirport: "AKL", arrivalAirport: "SFO", departureLocal: LocalMoment(rawValue: "2027-03-05T09:30"),
                              arrivalLocal: LocalMoment(rawValue: "2027-03-04T22:15")), bookingState: .booked))
        let activity = try item(trip, ItineraryInput(kind: .activity, title: "Museum", start: day("2027-03-05"), end: day("2027-03-05"),
                                startTime: clock("10:00"), endTime: clock("12:00")))
        let text = ItineraryText.make(trip: trip, items: [activity, flight])
        let first = try #require(text.range(of: day("2027-03-04").formatted))
        let second = try #require(text.range(of: day("2027-03-05").formatted))
        #expect(first.lowerBound < second.lowerBound)
        #expect(text.contains("22:15 — Arrival: Pacific flight"))
        #expect(text.contains("09:30 — Departure: Pacific flight"))
        #expect(text.contains("10:00–12:00 — Activity: Museum"))
        #expect(text.contains("AKL → SFO"))
        #expect(text.contains("Flight times are local to each airport."))
        #expect(text.contains("Booking state: Booked"))
        #expect(text == ItineraryText.make(trip: trip, items: [flight, activity]))
    }

    @Test func longStayDetailsAppearOnceButCheckInAndOutBothRemain() throws {
        let trip = trip()
        let stay = try item(trip, ItineraryInput(kind: .lodging, title: "Riverside hotel", start: day("2027-03-05"), end: day("2027-03-08"),
                            location: "London South Bank", notes: "Ask for late check-in.\nKeep luggage at reception.", startTime: clock("15:00"),
                            endTime: clock("11:00"), bookingState: .booked, reservationReference: "STAY-REF"))
        let text = ItineraryText.make(trip: trip, items: [stay], options: ItineraryTextOptions(includeNotes: true, includeReferences: true))
        #expect(text.contains("15:00 — Check-in: Riverside hotel"))
        #expect(text.contains("11:00 — Check-out: Riverside hotel"))
        #expect(text.components(separatedBy: "STAY-REF").count == 2)
        #expect(text.components(separatedBy: "Ask for late check-in.").count == 2)
        #expect(text.contains("    Keep luggage at reception."))
        #expect(text.contains("Location: London South Bank"))
        #expect(!text.contains(day("2027-03-06").formatted))
    }

    @Test func onlyCurrentSavedFlightDetailsAreShared() throws {
        let trip = trip()
        let old = FlightSchedule(number: "BA178", airline: "Old airline",
                                 departure: FlightStop(airport: "JFK", local: nil, timeZone: nil),
                                 arrival: FlightStop(airport: "LHR", local: nil, timeZone: nil),
                                 status: "Cancelled", provider: "Old provider", fetchedAt: .now)
        let flight = try item(trip, ItineraryInput(kind: .flight, title: "My flight", flight: FlightDetails(number: "BA178", airline: "Saved airline",
                              departureAirport: "EWR", arrivalAirport: "LGW", lastLookup: old)))
        let text = ItineraryText.make(trip: trip, items: [flight])
        #expect(text.contains("BA178 · Saved airline") && text.contains("EWR → LGW"))
        for oldValue in ["Old airline", "JFK", "LHR", "Cancelled", "Old provider"] { #expect(!text.contains(oldValue)) }
    }

    @Test func emptyAndUndatedPlansAndUnicodeProduceReadableText() throws {
        let trip = trip()
        let empty = ItineraryText.make(trip: trip, items: [])
        #expect(empty.contains(trip.name) && empty.contains("No itinerary items yet."))
        #expect(empty.contains("Dates to be decided"))
        let open = try item(trip, ItineraryInput(kind: .activity, title: "Café lunch ☕️", location: "São Paulo", bookingState: .idea))
        let text = ItineraryText.make(trip: trip, items: [open])
        #expect(text.contains("Undated plans") && text.contains("Time to be decided"))
        #expect(text.contains("Café lunch ☕️") && text.contains("São Paulo"))
        #expect(text.contains("Booking state: Idea"))
        #expect(String(data: Data(text.utf8), encoding: .utf8) == text)
        #expect(text.hasSuffix("\n"))
    }

    private func trip(notes: String = "") -> Trip {
        Trip(id: UUID().uuidString, input: TripInput(name: "London week", destinations: ["London"], plannedTravelers: 17,
                                                   budgetCents: 987_654_321, notes: notes), createdAt: Date(timeIntervalSince1970: 1_700_000_000))
    }
    private func item(_ trip: Trip, _ input: ItineraryInput) throws -> ItineraryItem {
        ItineraryItem(id: UUID().uuidString, tripID: trip.id, input: try input.validated(), createdAt: Date(timeIntervalSince1970: 1_700_000_000))
    }
    private func day(_ raw: String) -> TravelDay { TravelDay(rawValue: raw)! }
    private func clock(_ raw: String) -> LocalClock { LocalClock(rawValue: raw)! }
}
