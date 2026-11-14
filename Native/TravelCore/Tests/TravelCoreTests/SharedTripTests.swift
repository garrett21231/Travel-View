import Foundation
import GRDB
import Testing
@testable import TravelCore

struct SharedTripTests {
    @Test func aSingleTripFileRoundTripsAllSavedDetailsAndExcludesOtherTrips() throws {
        let package = try package()
        let foreign = ItineraryItem(id: UUID().uuidString, tripID: UUID().uuidString,
                                    input: ItineraryInput(kind: .activity, title: "Other trip secret"), createdAt: package.trip.createdAt)
        let scoped = try SharedTripPackage(trip: package.trip, items: package.items + [foreign])
        let data = try scoped.encoded()
        let copy = try SharedTripPackage.decode(data)
        #expect(copy.id == scoped.id && copy.exportedAt == scoped.exportedAt)
        #expect(copy.trip == package.trip && copy.items == package.items)
        #expect(copy.trip.budgetCents == 180_050 && copy.trip.plannedTravelers == 3)
        #expect(copy.items.first { $0.kind == .flight }?.flight?.lastLookup?.provider == "Saved provider")
        #expect(copy.items.first { $0.kind == .lodging }?.confirmationReference == "HOTEL-42")
        #expect(!String(decoding: data, as: UTF8.self).contains("Other trip secret"))
        #expect(throws: TripError.self) { try TripArchive.decode(data) }
        #expect(throws: TripError.self) { try SharedTripPackage.decode(TripArchive.encode([package.trip], items: package.items)) }
    }

    @Test func invalidFormatsFieldsRelationshipsAndOversizedFilesAreRejected() throws {
        let package = try package()
        let data = try package.encoded()
        for (field, value) in [("format", "unknown" as Any), ("version", 3), ("id", "bad-id"), ("exportedAt", NSNull())] {
            var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            json[field] = value
            #expect(throws: TripError.self) { try SharedTripPackage.decode(JSONSerialization.data(withJSONObject: json)) }
        }
        for change in 0...2 {
            var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            var items = try #require(json["items"] as? [[String: Any]])
            if change == 0 { items[0]["tripID"] = UUID().uuidString }
            if change == 1 { items.append(items[0]) }
            if change == 2 { items[0]["bookingState"] = "confirmed-by-provider" }
            json["items"] = items
            #expect(throws: TripError.self) { try SharedTripPackage.decode(JSONSerialization.data(withJSONObject: json)) }
        }
        #expect(throws: TripError.self) { try SharedTripPackage.decode(Data("broken".utf8)) }
        #expect(throws: TripError.self) { try SharedTripPackage.decode(Data(repeating: 0, count: SharedTripPackage.maximumBytes + 1)) }
    }

    @Test func importsCreateIndependentIdentitiesAndPreserveTiedTimelineOrder() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let package = try package()
        let target = try TripRepository(databaseURL: directory.appendingPathComponent("target.sqlite"))
        // Importing one's own file must not collide with or overwrite the original saved trip.
        _ = try await target.restore(TripArchive.encode([package.trip], items: package.items))
        let result = try await target.importSharedTrip(package)
        #expect(!result.alreadyImported && result.tripID != package.trip.id)
        #expect(result.snapshot.trips.count == 2 && result.snapshot.items.count == package.items.count * 2)
        let copy = try #require(result.snapshot.trips.first { $0.id == result.tripID })
        #expect(copy.input == package.trip.input)
        let copiedItems = result.snapshot.items.filter { $0.tripID == result.tripID }
        #expect(Set(copiedItems.map(\.id)).isDisjoint(with: Set(package.items.map(\.id))))
        #expect(ItineraryItem.ordered(copiedItems).map(\.input) == package.items.map(\.input))
        #expect(ItineraryTimeline.days(for: copiedItems).flatMap(\.events).map { $0.item.title } ==
                ItineraryTimeline.days(for: package.items).flatMap(\.events).map { $0.item.title })
        #expect(result.snapshot.sharedTripImports[package.id] == copy.id)
        let archive = try TripArchive.encode(result.snapshot.trips, items: result.snapshot.items)
        let restored = try TripRepository(databaseURL: directory.appendingPathComponent("backup.sqlite"))
        #expect(try await restored.restore(archive).items.count == package.items.count * 2)
    }

    @Test func reopeningTheSameFileKeepsTheImportedCopyAndNewerLocalEdits() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("target.sqlite")
        let repository = try TripRepository(databaseURL: url)
        let package = try package()
        let first = try await repository.importSharedTrip(package)
        let trip = try #require(first.snapshot.trips.first)
        var tripEdit = trip.input
        tripEdit.name = "My own edited trip"
        let edited = try await repository.save(tripEdit, id: trip.id)
        let item = try #require(first.snapshot.items.first)
        var itemEdit = item.input
        itemEdit.notes = "A note only on this device"
        let editedItem = try await repository.saveItem(itemEdit, id: item.id, tripID: trip.id)
        let reopened = try TripRepository(databaseURL: url)
        let repeated = try await reopened.importSharedTrip(SharedTripPackage.decode(package.encoded()))
        #expect(repeated.alreadyImported && repeated.tripID == first.tripID)
        #expect(repeated.snapshot.trips == [edited])
        #expect(repeated.snapshot.items.first { $0.id == item.id } == editedItem)
        #expect(repeated.snapshot.items.count == package.items.count)
    }

    @Test func concurrentImportsOfTheSameFileCreateOnlyOneCopy() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try TripRepository(databaseURL: directory.appendingPathComponent("trips.sqlite"))
        let package = try package()
        async let first = repository.importSharedTrip(package)
        async let second = repository.importSharedTrip(package)
        let (left, right) = try await (first, second)
        #expect(left.tripID == right.tripID)
        #expect(left.alreadyImported != right.alreadyImported)
        #expect(try await repository.loadSnapshot().trips.count == 1)
    }

    @Test func newlyExportedSnapshotsOfTheSameTripAreSeparateManualCopies() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try TripRepository(databaseURL: directory.appendingPathComponent("trips.sqlite"))
        let first = try package()
        let next = try SharedTripPackage(trip: first.trip, items: first.items)
        #expect(next.id != first.id)
        let original = try await repository.importSharedTrip(first)
        let later = try await repository.importSharedTrip(next)
        #expect(original.tripID != later.tripID)
        #expect(try await repository.loadSnapshot().trips.count == 2)
    }

    @Test func aFailedImportRollsBackTheTripItemsAndReceiptAndCanRetry() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("trips.sqlite")
        let repository = try TripRepository(databaseURL: url)
        let fixture = try DatabaseQueue(path: url.path)
        try await fixture.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_receipt BEFORE INSERT ON sharedTripImports BEGIN SELECT RAISE(ABORT, 'Test failure'); END")
        }
        let package = try package()
        await #expect(throws: (any Error).self) { try await repository.importSharedTrip(package) }
        let failed = try await repository.loadSnapshot()
        #expect(failed.trips.isEmpty && failed.items.isEmpty && failed.sharedTripImports.isEmpty)
        try await fixture.write { db in try db.execute(sql: "DROP TRIGGER reject_receipt") }
        let retried = try await repository.importSharedTrip(package)
        #expect(!retried.alreadyImported && retried.snapshot.items.count == package.items.count)
    }

    @Test func thePreviousSchemaAddsImportReceiptsWithoutChangingSavedPlans() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("v4.sqlite")
        let fixture = try DatabaseQueue(path: url.path)
        let package = try package()
        try await fixture.write { db in
            try db.execute(sql: """
                CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY);
                INSERT INTO grdb_migrations VALUES ('createTrips'), ('createItineraryItems'), ('addItineraryTimes'), ('addItineraryReservations');
                CREATE TABLE trips (id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL, destinations TEXT NOT NULL,
                    start TEXT, end TEXT, plannedTravelers INTEGER NOT NULL, budgetCents INTEGER, notes TEXT NOT NULL, createdAt DATETIME NOT NULL);
                CREATE TABLE itineraryItems (id TEXT PRIMARY KEY NOT NULL, tripID TEXT NOT NULL REFERENCES trips(id),
                    kind TEXT NOT NULL, title TEXT NOT NULL, start TEXT, end TEXT, location TEXT NOT NULL,
                    notes TEXT NOT NULL, flight TEXT, createdAt DATETIME NOT NULL, startTime TEXT, endTime TEXT,
                    bookingState TEXT NOT NULL DEFAULT 'planned', reservationReference TEXT NOT NULL DEFAULT '');
                """)
            try package.trip.insert(db)
            for item in package.items {
                // Write only the columns that existed in this fixture's schema.
                let flight = try item.flight.map {
                    String(decoding: try ItineraryItem.databaseJSONEncoder(for: "flight").encode($0), as: UTF8.self)
                }
                try db.execute(sql: """
                    INSERT INTO itineraryItems
                        (id, tripID, kind, title, start, end, location, notes, flight, createdAt,
                         startTime, endTime, bookingState, reservationReference)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [item.id, item.tripID, item.kind.rawValue, item.title, item.start?.rawValue,
                                      item.end?.rawValue, item.location, item.notes, flight, item.createdAt,
                                      item.startTime?.rawValue, item.endTime?.rawValue, item.bookingState.rawValue, item.reservationReference])
            }
        }
        let repository = try TripRepository(databaseURL: url)
        let snapshot = try await repository.loadSnapshot()
        #expect(snapshot.trips == [package.trip])
        #expect(ItineraryItem.ordered(snapshot.items) == package.items)
        #expect(snapshot.sharedTripImports.isEmpty)
        #expect(try await repository.importSharedTrip(package).snapshot.trips.count == 2)
    }

    private func package() throws -> SharedTripPackage {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let trip = Trip(id: UUID().uuidString, input: TripInput(name: "London", destinations: ["London"], plannedTravelers: 3,
                                                              budgetCents: 180_050, notes: "Trip notes ☕️"), createdAt: date)
        let schedule = FlightSchedule(number: "BA178", airline: "British Airways",
                                      departure: FlightStop(airport: "JFK", local: LocalMoment(rawValue: "2027-03-04T19:30"), timeZone: "America/New_York"),
                                      arrival: FlightStop(airport: "LHR", local: LocalMoment(rawValue: "2027-03-05T07:20"), timeZone: "Europe/London"),
                                      status: "Unknown", provider: "Saved provider", fetchedAt: date)
        var flight = FlightDetails(schedule: schedule)
        flight.bookingReference = "FLIGHT-42"
        let inputs = [ItineraryInput(kind: .flight, title: "Outbound", notes: "Seat note", flight: flight, bookingState: .booked),
                      ItineraryInput(kind: .lodging, title: "Hotel", start: TravelDay(rawValue: "2027-03-05"), end: TravelDay(rawValue: "2027-03-08"),
                                     location: "South Bank", startTime: LocalClock(rawValue: "15:00"), endTime: LocalClock(rawValue: "11:00"),
                                     bookingState: .booked, reservationReference: "HOTEL-42"),
                      ItineraryInput(kind: .activity, title: "Tied activity A", start: TravelDay(rawValue: "2027-03-05")),
                      ItineraryInput(kind: .activity, title: "Tied activity B", start: TravelDay(rawValue: "2027-03-05"), bookingState: .idea)]
        let items = try inputs.map { ItineraryItem(id: UUID().uuidString, tripID: trip.id, input: try $0.validated(), createdAt: date) }
        return try SharedTripPackage(trip: trip, items: items)
    }
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("SharedTripTests-\(UUID().uuidString)") }
}
