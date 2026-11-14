import Foundation
import GRDB
import Testing
@testable import TravelCore

struct TripDeletionTests {
    @Test func deletionRemovesOnlyTheChosenTripAndPersistsItsRecoveryEntry() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("trips.sqlite")
        let repository = try TripRepository(databaseURL: url)
        let imported = try await repository.importSharedTrip(package())
        let other = try await repository.save(TripInput(name: "Keep this trip"), id: UUID().uuidString)
        let otherItem = try await repository.saveItem(ItineraryInput(kind: .activity, title: "Keep this plan"),
                                                     id: UUID().uuidString, tripID: other.id)
        let result = try await repository.deleteTrip(id: imported.tripID.lowercased())
        #expect(result.trips == [other] && result.items == [otherItem])
        #expect(result.sharedTripImports.isEmpty)
        let deleted = try #require(result.deletedTrips.first)
        #expect(deleted.tripID == imported.tripID && deleted.name == "London" && deleted.itemCount == 3)
        let reopened = try TripRepository(databaseURL: url)
        let persisted = try await reopened.loadSnapshot()
        #expect(persisted.trips == result.trips && persisted.items == result.items && persisted.deletedTrips == result.deletedTrips)
        // Ordinary backups contain the active collection, not the private recovery payload.
        let backup = try TripArchive.decode(TripArchive.encode(result.trips, items: result.items))
        #expect(backup.trips == [other] && backup.items == [otherItem])
    }

    @Test func restoringTheLastTripRecoversEveryFieldIdentityAndReceipt() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("trips.sqlite")
        let repository = try TripRepository(databaseURL: url)
        let original = try await repository.importSharedTrip(package())
        let deleted = try await repository.deleteTrip(id: original.tripID)
        #expect(deleted.trips.isEmpty && deleted.items.isEmpty && deleted.sharedTripImports.isEmpty)
        let entry = try #require(deleted.deletedTrips.first)
        let reopened = try TripRepository(databaseURL: url)
        let restored = try await reopened.restoreDeletedTrip(id: entry.id)
        #expect(restored.tripID == original.tripID)
        #expect(restored.snapshot.trips == original.snapshot.trips)
        #expect(ItineraryItem.ordered(restored.snapshot.items) == ItineraryItem.ordered(original.snapshot.items))
        #expect(restored.snapshot.sharedTripImports == original.snapshot.sharedTripImports)
        #expect(restored.snapshot.deletedTrips.isEmpty)
        await #expect(throws: TripError.self) { try await reopened.restoreDeletedTrip(id: entry.id) }
    }

    @Test func aFailedCascadeRollsBackTheRecoveryEntryAndAllActiveRecords() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("trips.sqlite")
        let repository = try TripRepository(databaseURL: url)
        let original = try await repository.importSharedTrip(package())
        let fixture = try DatabaseQueue(path: url.path)
        try await fixture.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_trip_delete BEFORE DELETE ON itineraryItems BEGIN SELECT RAISE(ABORT, 'Test failure'); END")
        }
        await #expect(throws: (any Error).self) { try await repository.deleteTrip(id: original.tripID) }
        let failed = try await repository.loadSnapshot()
        #expect(failed.trips == original.snapshot.trips && failed.items == original.snapshot.items)
        #expect(failed.sharedTripImports == original.snapshot.sharedTripImports && failed.deletedTrips.isEmpty)
        try await fixture.write { db in try db.execute(sql: "DROP TRIGGER reject_trip_delete") }
        #expect(try await repository.deleteTrip(id: original.tripID).deletedTrips.count == 1)
    }

    @Test func aFailedRestorationKeepsTheDeletedTripAndCanRetry() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("trips.sqlite")
        let repository = try TripRepository(databaseURL: url)
        let original = try await repository.importSharedTrip(package())
        let deleted = try await repository.deleteTrip(id: original.tripID)
        let entry = try #require(deleted.deletedTrips.first)
        let fixture = try DatabaseQueue(path: url.path)
        try await fixture.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_trip_restore BEFORE INSERT ON itineraryItems WHEN NEW.kind = 'lodging' BEGIN SELECT RAISE(ABORT, 'Test failure'); END")
        }
        await #expect(throws: (any Error).self) { try await repository.restoreDeletedTrip(id: entry.id) }
        let failed = try await repository.loadSnapshot()
        #expect(failed.trips.isEmpty && failed.items.isEmpty && failed.sharedTripImports.isEmpty)
        #expect(failed.deletedTrips == deleted.deletedTrips)
        try await fixture.write { db in try db.execute(sql: "DROP TRIGGER reject_trip_restore") }
        let retried = try await repository.restoreDeletedTrip(id: entry.id)
        #expect(retried.snapshot.trips == original.snapshot.trips && retried.snapshot.items.count == 3)
    }

    @Test func restorationNeverOverwritesATripImportedFromABackupAfterDeletion() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try TripRepository(databaseURL: directory.appendingPathComponent("trips.sqlite"))
        let original = try await repository.importSharedTrip(package())
        let deleted = try await repository.deleteTrip(id: original.tripID)
        let entry = try #require(deleted.deletedTrips.first)
        let archive = try TripArchive.encode(original.snapshot.trips, items: original.snapshot.items)
        _ = try await repository.restore(archive)
        var newer = try #require(original.snapshot.trips.first).input
        newer.notes = "Newer local changes"
        let edited = try await repository.save(newer, id: original.tripID, expectingExisting: true)
        await #expect(throws: TripError.self) { try await repository.restoreDeletedTrip(id: entry.id) }
        let result = try await repository.loadSnapshot()
        #expect(result.trips == [edited] && result.items.count == 3 && result.deletedTrips == deleted.deletedTrips)
    }

    @Test func reimportingADeletedSharedFileKeepsItsNewerReceiptWhenTheOldCopyIsRestored() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try TripRepository(databaseURL: directory.appendingPathComponent("trips.sqlite"))
        let package = try package()
        let original = try await repository.importSharedTrip(package)
        let deleted = try await repository.deleteTrip(id: original.tripID)
        let entry = try #require(deleted.deletedTrips.first)
        let reimported = try await repository.importSharedTrip(package)
        #expect(!reimported.alreadyImported && reimported.tripID != original.tripID)
        let restored = try await repository.restoreDeletedTrip(id: entry.id)
        #expect(restored.snapshot.trips.count == 2 && restored.snapshot.items.count == 6)
        #expect(restored.snapshot.sharedTripImports[package.id] == reimported.tripID)
        let reopenedFile = try await repository.importSharedTrip(package)
        #expect(reopenedFile.alreadyImported && reopenedFile.tripID == reimported.tripID && reopenedFile.snapshot.trips.count == 2)
    }

    @Test func staleEditorsAndInvalidRequestsCannotRecreateADeletedTrip() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try TripRepository(databaseURL: directory.appendingPathComponent("trips.sqlite"))
        let original = try await repository.importSharedTrip(package())
        let trip = try #require(original.snapshot.trips.first)
        let item = try #require(original.snapshot.items.first)
        _ = try await repository.deleteTrip(id: trip.id)
        await #expect(throws: TripError.self) { try await repository.save(trip.input, id: trip.id, expectingExisting: true) }
        await #expect(throws: TripError.self) { try await repository.saveItem(item.input, id: item.id, tripID: trip.id) }
        await #expect(throws: TripError.self) { try await repository.deleteTrip(id: trip.id) }
        await #expect(throws: TripError.self) { try await repository.deleteTrip(id: "bad-id") }
        await #expect(throws: TripError.self) { try await repository.restoreDeletedTrip(id: "bad-id") }
        let result = try await repository.loadSnapshot()
        #expect(result.trips.isEmpty && result.items.isEmpty && result.deletedTrips.count == 1)
        // New drafts and their save retries still use the same creation path.
        let newID = UUID().uuidString
        let first = try await repository.save(TripInput(name: "New draft"), id: newID)
        #expect(try await repository.save(first.input, id: newID) == first)
    }

    @Test func concurrentDeleteAndRestoreRequestsCreateOnlyOneRecoveryEntryAndOneTrip() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try TripRepository(databaseURL: directory.appendingPathComponent("trips.sqlite"))
        let original = try await repository.importSharedTrip(package())
        async let firstDelete = try? repository.deleteTrip(id: original.tripID)
        async let secondDelete = try? repository.deleteTrip(id: original.tripID)
        let (first, second) = await (firstDelete, secondDelete)
        #expect((first == nil) != (second == nil))
        let entry = try #require(try await repository.loadSnapshot().deletedTrips.first)
        async let firstRestore = try? repository.restoreDeletedTrip(id: entry.id)
        async let secondRestore = try? repository.restoreDeletedTrip(id: entry.id)
        let (left, right) = await (firstRestore, secondRestore)
        #expect((left == nil) != (right == nil))
        let restored = try await repository.loadSnapshot()
        #expect(restored.trips == original.snapshot.trips && restored.items.count == 3 && restored.deletedTrips.isEmpty)
    }

    @Test func thePreviousSchemaGainsRecoveryStorageWithoutChangingExistingTripsOrReceipts() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("trips.sqlite")
        let original: TripRepository.Snapshot
        do {
            let previous = try TripRepository(databaseURL: url)
            original = try await previous.importSharedTrip(package()).snapshot
        }
        let fixture = try DatabaseQueue(path: url.path)
        try await fixture.write { db in
            try db.execute(sql: "DROP TABLE checklistItems; DROP TABLE deletedTrips; DELETE FROM grdb_migrations WHERE identifier IN ('createDeletedTrips', 'createTripChecklists')")
        }
        let upgraded = try TripRepository(databaseURL: url)
        let snapshot = try await upgraded.loadSnapshot()
        #expect(snapshot.trips == original.trips && snapshot.items == original.items)
        #expect(snapshot.sharedTripImports == original.sharedTripImports && snapshot.deletedTrips.isEmpty)
        #expect(try await upgraded.deleteTrip(id: original.trips[0].id).deletedTrips.count == 1)
    }

    @Test func permanentDeletionRemovesOnlyTheSelectedRecoveryEntryAndKeepsAnActiveBackupCopy() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("trips.sqlite")
        let repository = try TripRepository(databaseURL: url)
        let original = try await repository.importSharedTrip(package())
        let deleted = try await repository.deleteTrip(id: original.tripID)
        let selected = try #require(deleted.deletedTrips.first)
        let other = try await repository.save(TripInput(name: "Keep this recovery entry"), id: UUID().uuidString)
        _ = try await repository.deleteTrip(id: other.id)
        _ = try await repository.restore(TripArchive.encode(original.snapshot.trips, items: original.snapshot.items))
        let before = try await repository.loadSnapshot()
        let result = try await repository.permanentlyDeleteTrip(id: selected.id.lowercased())
        #expect(result.trips == before.trips && result.items == before.items)
        #expect(result.sharedTripImports == before.sharedTripImports)
        #expect(result.deletedTrips == before.deletedTrips.filter { $0.id != selected.id })
        let reopened = try TripRepository(databaseURL: url)
        let persisted = try await reopened.loadSnapshot()
        #expect(persisted.deletedTrips == result.deletedTrips)
        await #expect(throws: TripError.self) { try await reopened.restoreDeletedTrip(id: selected.id) }
    }

    @Test func failedPermanentDeletionPreservesRecoveryAndCanRetry() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("trips.sqlite")
        let repository = try TripRepository(databaseURL: url)
        let original = try await repository.importSharedTrip(package())
        let deleted = try await repository.deleteTrip(id: original.tripID)
        let selected = try #require(deleted.deletedTrips.first)
        let fixture = try DatabaseQueue(path: url.path)
        try await fixture.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_permanent_delete BEFORE DELETE ON deletedTrips BEGIN SELECT RAISE(ABORT, 'Test failure'); END")
        }
        await #expect(throws: (any Error).self) { try await repository.permanentlyDeleteTrip(id: selected.id) }
        let failed = try await repository.loadSnapshot()
        #expect(failed.deletedTrips == deleted.deletedTrips && failed.trips.isEmpty && failed.items.isEmpty)
        try await fixture.write { db in try db.execute(sql: "DROP TRIGGER reject_permanent_delete") }
        let retry = try await repository.permanentlyDeleteTrip(id: selected.id)
        #expect(retry.deletedTrips.isEmpty && retry.trips.isEmpty && retry.items.isEmpty && retry.sharedTripImports.isEmpty)
    }

    @Test func permanentDeletionRejectsInvalidMissingAndRestoredEntryIDsWithoutTouchingTheTrip() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try TripRepository(databaseURL: directory.appendingPathComponent("trips.sqlite"))
        let original = try await repository.importSharedTrip(package())
        let deleted = try await repository.deleteTrip(id: original.tripID)
        let selected = try #require(deleted.deletedTrips.first)
        await #expect(throws: TripError.self) { try await repository.permanentlyDeleteTrip(id: "bad-id") }
        await #expect(throws: TripError.self) { try await repository.permanentlyDeleteTrip(id: UUID().uuidString) }
        #expect(try await repository.loadSnapshot().deletedTrips == deleted.deletedTrips)
        let restored = try await repository.restoreDeletedTrip(id: selected.id)
        await #expect(throws: TripError.self) { try await repository.permanentlyDeleteTrip(id: selected.id) }
        let result = try await repository.loadSnapshot()
        #expect(result.trips == restored.snapshot.trips && result.items == restored.snapshot.items)
        #expect(result.sharedTripImports == restored.snapshot.sharedTripImports && result.deletedTrips.isEmpty)
    }

    @Test func anUnreadableRecoveryPayloadCanStillBePermanentlyRemoved() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("trips.sqlite")
        let repository = try TripRepository(databaseURL: url)
        let original = try await repository.importSharedTrip(package())
        let deleted = try await repository.deleteTrip(id: original.tripID)
        let selected = try #require(deleted.deletedTrips.first)
        let fixture = try DatabaseQueue(path: url.path)
        try await fixture.write { db in
            try db.execute(sql: "UPDATE deletedTrips SET contents = ? WHERE id = ?", arguments: [Data("broken".utf8), selected.id])
        }
        await #expect(throws: TripError.self) { try await repository.restoreDeletedTrip(id: selected.id) }
        #expect(try await repository.permanentlyDeleteTrip(id: selected.id).deletedTrips.isEmpty)
    }

    @Test func concurrentRestoreAndPermanentDeleteHaveOneCompleteOutcome() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try TripRepository(databaseURL: directory.appendingPathComponent("trips.sqlite"))
        let original = try await repository.importSharedTrip(package())
        let deleted = try await repository.deleteTrip(id: original.tripID)
        let selected = try #require(deleted.deletedTrips.first)
        async let restoration = try? repository.restoreDeletedTrip(id: selected.id)
        async let removal = try? repository.permanentlyDeleteTrip(id: selected.id)
        let (restored, removed) = await (restoration, removal)
        #expect((restored == nil) != (removed == nil))
        let final = try await repository.loadSnapshot()
        #expect(final.deletedTrips.isEmpty)
        if restored != nil {
            #expect(final.trips == original.snapshot.trips && final.items == original.snapshot.items)
            #expect(final.sharedTripImports == original.snapshot.sharedTripImports)
        } else {
            #expect(final.trips.isEmpty && final.items.isEmpty && final.sharedTripImports.isEmpty)
        }
    }

    private func package() throws -> SharedTripPackage {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let trip = Trip(id: UUID().uuidString,
                        input: TripInput(name: "London", destinations: ["London"], plannedTravelers: 3, budgetCents: 180_050, notes: "Trip notes"),
                        createdAt: date)
        let schedule = FlightSchedule(number: "BA178", airline: "British Airways",
                                      departure: FlightStop(airport: "JFK", local: LocalMoment(rawValue: "2027-03-04T19:30"), timeZone: "America/New_York"),
                                      arrival: FlightStop(airport: "LHR", local: LocalMoment(rawValue: "2027-03-05T07:20"), timeZone: "Europe/London"),
                                      status: "Unknown", provider: "Saved provider", fetchedAt: date)
        var flight = FlightDetails(schedule: schedule)
        flight.bookingReference = "FLIGHT-42"
        let inputs = [ItineraryInput(kind: .flight, title: "Outbound", notes: "Seat note", flight: flight, bookingState: .booked),
                      ItineraryInput(kind: .lodging, title: "Hotel", start: TravelDay(rawValue: "2027-03-05"), end: TravelDay(rawValue: "2027-03-08"),
                                     location: "South Bank", notes: "Check-in note", startTime: LocalClock(rawValue: "15:00"), endTime: LocalClock(rawValue: "11:00"),
                                     bookingState: .booked, reservationReference: "HOTEL-42"),
                      ItineraryInput(kind: .activity, title: "Walk", bookingState: .idea)]
        let items = try inputs.map { ItineraryItem(id: UUID().uuidString, tripID: trip.id, input: try $0.validated(), createdAt: date) }
        return try SharedTripPackage(trip: trip, items: items)
    }

    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("TripDeletionTests-\(UUID().uuidString)") }
}
