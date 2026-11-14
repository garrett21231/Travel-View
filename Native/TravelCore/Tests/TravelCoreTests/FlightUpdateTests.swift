import Foundation
import Testing
@testable import TravelCore

struct FlightUpdateTests {
    @Test func defaultsApplyUntouchedFieldsAndProtectManualEditsAndPersonalDetails() throws {
        let original = schedule()
        var plan = FlightDetails(schedule: original)
        plan.departureLocal = LocalMoment(rawValue: "2027-03-04T20:05")
        plan.bookingReference = "KEEP-ME"
        let item = item(plan)
        let latest = schedule(departure: "2027-03-04T20:00", arrival: "2027-03-05T07:50", airline: "Updated airline")
        let review = try FlightUpdate(item: item, schedule: latest)
        #expect(review.defaultSelection == [.airline, .arrivalTime])
        #expect(review.changes.first { $0.field == .departureTime }?.differsFromLookup == true)
        let saved = try review.applying(review.defaultSelection)
        #expect(saved.flight?.departureLocal?.clock == "20:05")
        #expect(saved.flight?.arrivalLocal?.clock == "07:50")
        #expect(saved.flight?.airline == "Updated airline")
        #expect(saved.flight?.bookingReference == "KEEP-ME")
        #expect(saved.bookingState == .booked)
        #expect(saved.title == item.title)
        #expect(saved.notes == item.notes)
        #expect(saved.location == item.location)
        #expect(saved.flight?.lastLookup == latest)
    }

    @Test func manuallyEnteredFlightsRequireExplicitChoicesAndCanSaveOnlyTheLookup() throws {
        let plan = FlightDetails(number: "BA178", airline: "My airline", departureAirport: "JFK", arrivalAirport: "LHR",
                                 departureLocal: LocalMoment(rawValue: "2027-03-04T19:00"), bookingReference: "MANUAL")
        let item = item(plan)
        let review = try FlightUpdate(item: item, schedule: schedule())
        #expect(!review.hasComparableLookup)
        #expect(review.defaultSelection.isEmpty)
        let lookupOnly = try review.applying([])
        var expected = plan
        expected.lastLookup = review.schedule
        #expect(lookupOnly.flight == expected)
        let selected = try review.applying([.arrivalTime])
        #expect(selected.flight?.departureLocal == plan.departureLocal)
        #expect(selected.flight?.arrivalLocal == review.schedule.arrival.local)
        #expect(selected.end == review.schedule.arrival.local?.day)
        #expect(selected.flight?.airline == "My airline")
    }

    @Test func missingProviderValuesNeverEraseKnownTimesOrAirline() throws {
        let old = schedule()
        let review = try FlightUpdate(item: item(FlightDetails(schedule: old)),
                                     schedule: schedule(departure: nil, arrival: nil, airline: ""))
        #expect(review.changes.isEmpty)
        let saved = try review.applying([])
        #expect(saved.flight?.departureLocal == old.departure.local)
        #expect(saved.flight?.arrivalLocal == old.arrival.local)
        #expect(saved.flight?.airline == old.airline)
    }

    @Test func wrongFlightsWrongDatesAndUnavailableSelectionsAreRejected() throws {
        let item = item(FlightDetails(schedule: schedule()))
        #expect(throws: TripError.self) { try FlightUpdate(item: item, schedule: self.schedule(number: "BA179")) }
        #expect(throws: TripError.self) { try FlightUpdate(item: item, schedule: self.schedule(departure: "2027-03-06T19:30")) }
        let review = try FlightUpdate(item: item, schedule: schedule())
        #expect(throws: TripError.self) { try review.applying([.departureTime]) }
        let undated = ItineraryItem(id: UUID().uuidString, tripID: item.tripID,
                                   input: ItineraryInput(kind: .flight, title: "Open", flight: FlightDetails(number: "BA178")), createdAt: item.createdAt)
        #expect(throws: TripError.self) { try FlightUpdate(item: undated, schedule: self.schedule()) }
    }

    @Test func changingTheFlightIdentityInvalidatesTheOldAutomaticSelectionBaseline() throws {
        var plan = FlightDetails(schedule: schedule(number: "BA179"))
        plan.number = "BA178"
        let review = try FlightUpdate(item: item(plan), schedule: schedule(departure: "2027-03-04T20:00"))
        #expect(!review.hasComparableLookup)
        #expect(review.defaultSelection.isEmpty)
    }

    @Test func declinedUpdatesRemainProtectedDuringLaterChecks() throws {
        let first = try FlightUpdate(item: item(FlightDetails(schedule: schedule())),
                                     schedule: schedule(departure: "2027-03-04T20:00"))
        let kept = try first.applying([])
        let nextItem = ItineraryItem(id: first.base.id, tripID: first.base.tripID, input: kept, createdAt: first.base.createdAt)
        let next = try FlightUpdate(item: nextItem, schedule: schedule(departure: "2027-03-04T20:30"))
        #expect(next.defaultSelection.isEmpty)
        #expect(next.changes.first?.differsFromLookup == true)
        #expect(try next.applying([]).flight?.departureLocal?.clock == "19:30")
    }

    @Test func transactionalUpdatesKeepIdentityAndSurviveReopeningAndBackup() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("trips.sqlite")
        let repository = try TripRepository(databaseURL: url)
        let trip = try await repository.save(TripInput(name: "London"), id: UUID().uuidString)
        let base = try await repository.saveItem(item(FlightDetails(schedule: schedule())).input, id: UUID().uuidString, tripID: trip.id)
        let review = try FlightUpdate(item: base, schedule: schedule(arrival: "2027-03-06T08:00"))
        let saved = try await repository.applyFlightUpdate(review, selection: [.arrivalTime])
        #expect(saved.id == base.id)
        #expect(saved.tripID == base.tripID)
        #expect(saved.createdAt == base.createdAt)
        #expect(saved.end == TravelDay(rawValue: "2027-03-06"))
        let reopened = try TripRepository(databaseURL: url)
        #expect(try await reopened.loadSnapshot().items == [saved])
        let archive = try TripArchive.encode([trip], items: [saved])
        let restored = try TripRepository(databaseURL: directory.appendingPathComponent("restore.sqlite"))
        #expect(try await restored.restore(archive).items == [saved])
    }

    @Test func reviewsCannotOverwriteNewerEditsOrRecreateDeletedFlights() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try TripRepository(databaseURL: directory.appendingPathComponent("trips.sqlite"))
        let trip = try await repository.save(TripInput(name: "London"), id: UUID().uuidString)
        let base = try await repository.saveItem(item(FlightDetails(schedule: schedule())).input, id: UUID().uuidString, tripID: trip.id)
        let review = try FlightUpdate(item: base, schedule: schedule(arrival: "2027-03-05T08:00"))
        var edited = base.input
        edited.bookingState = .idea
        let newer = try await repository.saveItem(edited, id: base.id, tripID: trip.id)
        await #expect(throws: TripError.self) { try await repository.applyFlightUpdate(review, selection: review.defaultSelection) }
        #expect(try await repository.loadSnapshot().items == [newer])
        try await repository.deleteItem(id: base.id, tripID: trip.id)
        await #expect(throws: TripError.self) { try await repository.applyFlightUpdate(review, selection: review.defaultSelection) }
        #expect(try await repository.loadSnapshot().items.isEmpty)
    }

    private func schedule(number: String = "BA178", departure: String? = "2027-03-04T19:30",
                          arrival: String? = "2027-03-05T07:20", airline: String = "British Airways") -> FlightSchedule {
        FlightSchedule(number: number, airline: airline,
                       departure: FlightStop(airport: "JFK", local: departure.flatMap(LocalMoment.init(rawValue:)), timeZone: "America/New_York"),
                       arrival: FlightStop(airport: "LHR", local: arrival.flatMap(LocalMoment.init(rawValue:)), timeZone: "Europe/London"),
                       status: "Unknown", provider: "Test provider", fetchedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }
    private func item(_ plan: FlightDetails) -> ItineraryItem {
        ItineraryItem(id: UUID().uuidString, tripID: UUID().uuidString,
                      input: ItineraryInput(kind: .flight, title: "My flight", start: TravelDay(rawValue: "2027-03-04"),
                                            end: TravelDay(rawValue: "2027-03-05"), location: "Keep location", notes: "Keep my notes", flight: plan,
                                            bookingState: .booked),
                      createdAt: Date(timeIntervalSince1970: 1_700_000_000))
    }
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("FlightUpdateTests-\(UUID().uuidString)") }
}
