import Foundation
import GRDB
import Testing
@testable import TravelCore

struct ItineraryTests {
    @Test func upgradesAnExistingTripsOnlyDatabaseWithoutLosingTrips() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("old.sqlite")
        let old = try DatabaseQueue(path: url.path)
        // A fixture of the first shipped native schema, including its completed migration.
        try await old.write { db in
            try db.execute(sql: """
                CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY);
                INSERT INTO grdb_migrations VALUES ('createTrips');
                CREATE TABLE trips (id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL, destinations TEXT NOT NULL,
                    start TEXT, end TEXT, plannedTravelers INTEGER NOT NULL, budgetCents INTEGER, notes TEXT NOT NULL, createdAt DATETIME NOT NULL);
                """)
            try Trip(id: UUID().uuidString, input: TripInput(name: "Existing plan"),
                     createdAt: Date(timeIntervalSince1970: 1_700_000_000)).insert(db)
        }
        let repository = try TripRepository(databaseURL: url)
        let snapshot = try await repository.loadSnapshot()
        #expect(snapshot.trips.map(\.name) == ["Existing plan"])
        #expect(snapshot.items.isEmpty)
        _ = try await repository.saveItem(ItineraryInput(kind: .lodging, title: "Hotel"), id: UUID().uuidString,
                                          tripID: snapshot.trips[0].id)
        #expect(try await repository.loadSnapshot().items.count == 1)
    }

    @Test func itemRetriesEditingReopeningAndTripOwnershipArePreserved() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("trips.sqlite")
        let repository = try TripRepository(databaseURL: url)
        let trip = try await repository.save(TripInput(name: "Tokyo"), id: UUID().uuidString)
        let other = try await repository.save(TripInput(name: "Other"), id: UUID().uuidString)
        let input = ItineraryInput(kind: .activity, title: "  Museum  ", start: TravelDay(rawValue: "2027-03-04"))
        let id = UUID().uuidString
        async let first = repository.saveItem(input, id: id, tripID: trip.id)
        async let second = repository.saveItem(input, id: id, tripID: trip.id)
        let (saved, retry) = try await (first, second)
        #expect(saved == retry)
        #expect(saved.title == "Museum")
        var edit = saved.input
        edit.notes = "Book ahead"
        let edited = try await repository.saveItem(edit, id: id, tripID: trip.id)
        #expect(edited.createdAt == saved.createdAt)
        let reopened = try TripRepository(databaseURL: url)
        #expect(try await reopened.loadSnapshot().items == [edited])
        await #expect(throws: TripError.self) { try await repository.saveItem(edit, id: id, tripID: other.id) }
        await #expect(throws: TripError.self) { try await repository.deleteItem(id: id, tripID: other.id) }
        try await repository.deleteItem(id: id, tripID: trip.id)
        #expect(try await repository.loadSnapshot().items.isEmpty)
    }

    @Test func airportWallClocksAndDateLineCrossingsRoundTrip() async throws {
        #expect(LocalMoment(rawValue: "2027-02-30T12:30") == nil)
        #expect(LocalMoment(rawValue: "2027-03-04T24:00") == nil)
        let departure = try #require(LocalMoment(rawValue: "2027-03-05T09:30"))
        let arrival = try #require(LocalMoment(rawValue: "2027-03-04T22:15"))
        #expect(LocalMoment(day: departure.day, clockFrom: departure.pickerDate) == departure)
        let flight = FlightDetails(number: " nz 8 ", airline: "Air New Zealand", departureAirport: "akl", arrivalAirport: "sfo",
                                   departureLocal: departure, arrivalLocal: arrival)
        let value = try ItineraryInput(kind: .flight, title: "Across the Pacific", flight: flight).validated()
        #expect(value.start == departure.day)
        #expect(value.end == arrival.day)
        #expect(value.flight?.number == "NZ8")
        #expect(value.flight?.departureAirport == "AKL")
        #expect(throws: TripError.self) {
            try ItineraryInput(kind: .lodging, title: "Hotel", start: departure.day, end: arrival.day).validated()
        }
        let data = try JSONEncoder().encode(flight)
        #expect(try JSONDecoder().decode(FlightDetails.self, from: data) == flight)
    }

    @Test func v2BackupsIncludeItemsAndV1BackupsStillImport() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try TripRepository(databaseURL: directory.appendingPathComponent("source.sqlite"))
        let trip = try await source.save(TripInput(name: "London"), id: UUID().uuidString)
        let item = try await source.saveItem(ItineraryInput(kind: .flight, title: "Outbound", flight: FlightDetails(number: "BA178")),
                                             id: UUID().uuidString, tripID: trip.id)
        let data = try TripArchive.encode([trip], items: [item])
        let target = try TripRepository(databaseURL: directory.appendingPathComponent("target.sqlite"))
        let imported = try await target.restore(data)
        #expect(imported.items == [item])
        #expect(imported.addedItems == 1)
        var edit = item.input
        edit.title = "Edited locally"
        let edited = try await target.saveItem(edit, id: item.id, tripID: trip.id)
        let retry = try await target.restore(data)
        #expect(retry.addedItems == 0)
        #expect(retry.items == [edited])

        var v1 = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        v1["version"] = 1
        v1.removeValue(forKey: "items")
        let oldTarget = try TripRepository(databaseURL: directory.appendingPathComponent("v1.sqlite"))
        let oldImport = try await oldTarget.restore(JSONSerialization.data(withJSONObject: v1))
        #expect(oldImport.trips == [trip])
        #expect(oldImport.items.isEmpty)
    }

    @Test func aReviewedFlightAndItsOriginalLookupSurviveReopeningAndBackup() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("flight.sqlite")
        let repository = try TripRepository(databaseURL: url)
        let trip = try await repository.save(TripInput(name: "London"), id: UUID().uuidString)
        let lookup = FlightSchedule(number: "BA178", airline: "British Airways",
                                    departure: FlightStop(airport: "JFK", local: LocalMoment(rawValue: "2027-03-04T19:30"), timeZone: "America/New_York"),
                                    arrival: FlightStop(airport: "LHR", local: LocalMoment(rawValue: "2027-03-05T07:20"), timeZone: "Europe/London"),
                                    status: "Unknown", provider: "AeroDataBox", fetchedAt: Date(timeIntervalSince1970: 1_700_000_000))
        var reviewed = FlightDetails(schedule: lookup)
        reviewed.departureLocal = LocalMoment(rawValue: "2027-03-04T20:00")
        reviewed.bookingReference = "MYPLAN"
        let item = try await repository.saveItem(ItineraryInput(kind: .flight, title: "Reviewed flight", flight: reviewed),
                                                 id: UUID().uuidString, tripID: trip.id)
        let reopened = try TripRepository(databaseURL: url)
        let snapshot = try await reopened.loadSnapshot()
        #expect(snapshot.items == [item])
        #expect(snapshot.items[0].flight?.lastLookup == lookup)
        #expect(snapshot.items[0].flight?.departureLocal?.clock == "20:00")
        let data = try TripArchive.encode(snapshot.trips, items: snapshot.items)
        let target = try TripRepository(databaseURL: directory.appendingPathComponent("restored.sqlite"))
        #expect(try await target.restore(data).items == [item])
    }

    @Test func failedItemImportRollsBackNewTripsAndOrphanBackupsAreRejected() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try TripRepository(databaseURL: directory.appendingPathComponent("source.sqlite"))
        let trip = try await source.save(TripInput(name: "Plan"), id: UUID().uuidString)
        let item = try await source.saveItem(ItineraryInput(kind: .activity, title: "Reject"), id: UUID().uuidString, tripID: trip.id)
        let backup = try TripArchive.encode([trip], items: [item])
        let url = directory.appendingPathComponent("target.sqlite")
        let target = try TripRepository(databaseURL: url)
        let fixture = try DatabaseQueue(path: url.path)
        try await fixture.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_item BEFORE INSERT ON itineraryItems BEGIN SELECT RAISE(ABORT, 'Test failure'); END")
        }
        await #expect(throws: (any Error).self) { try await target.restore(backup) }
        #expect(try await target.loadSnapshot().trips.isEmpty)
        #expect(try await target.loadSnapshot().items.isEmpty)
        let orphan = try TripArchive.encode([], items: [item])
        await #expect(throws: TripError.self) { try await target.restore(orphan) }
    }

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ItineraryTests-\(UUID().uuidString)")
    }
}
