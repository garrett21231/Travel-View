import Foundation
import GRDB
import Testing
@testable import TravelCore

struct TransportTests {
    private let day = TravelDay(rawValue: "2027-04-12")!
    private let nextDay = TravelDay(rawValue: "2027-04-13")!

    @Test(arguments: TransportMode.allCases)
    func modesPersistEditAndReopen(mode: TransportMode) async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("trips.sqlite")
        let repository = try TripRepository(databaseURL: url)
        let trip = try await repository.save(TripInput(name: "Transport QA"), id: UUID().uuidString)
        var input = plan(mode: mode)
        let item = try await repository.saveItem(input, id: UUID().uuidString, tripID: trip.id)
        #expect(item.transport?.operatorName == "Example Rail")
        #expect(item.transport?.departure == "Paris Gare du Nord")
        #expect(item.transport?.arrival == "London St Pancras")
        #expect(item.confirmationReference == "TRAIN-42")
        input = item.input
        input.notes = "Platform announced later"
        let edit = try await repository.saveItem(input, id: item.id, tripID: trip.id)
        #expect(edit.createdAt == item.createdAt)
        let reopened = try TripRepository(databaseURL: url)
        #expect(try await reopened.loadSnapshot().items == [edit])
    }

    @Test func validatesRequiredDetailsLimitsAndLocalClocks() throws {
        #expect(throws: TripError.self) { try ItineraryInput(kind: .transport, title: "Train").validated() }
        var input = plan()
        // London can have an earlier local clock than Paris. No time zone is inferred from place text.
        input.startTime = LocalClock(rawValue: "10:00")
        input.endTime = LocalClock(rawValue: "09:45")
        #expect(try input.validated().endTime == input.endTime)
        input.end = TravelDay(rawValue: "2027-04-11")
        #expect(try input.validated().end == input.end)
        input.start = nil
        #expect(throws: TripError.self) { try input.validated() }
        input.startTime = nil
        #expect(throws: TripError.self) { try input.validated() }
        input = plan()
        input.end = nil
        #expect(throws: TripError.self) { try input.validated() }
        for field in 0...2 {
            input = plan()
            if field == 0 { input.transport?.operatorName = String(repeating: "a", count: 161) }
            if field == 1 { input.transport?.departure = String(repeating: "a", count: 301) }
            if field == 2 { input.transport?.arrival = String(repeating: "a", count: 301) }
            #expect(throws: TripError.self) { try input.validated() }
        }
        input = plan()
        input.flight = FlightDetails(number: "BA178")
        #expect(try input.validated().flight == nil)
        input.kind = .activity
        #expect(try input.validated().transport == nil)
        input.kind = .flight
        #expect(try input.validated().transport == nil)
        #expect(try ItineraryInput(kind: .transport, title: "Ferry idea", transport: .init(mode: .ferry)).validated().start == nil)
    }

    @Test func timelineSearchCountsAndReadableExportUseOnePlanWithTwoStops() throws {
        let trip = Trip(id: UUID().uuidString, input: TripInput(name: "Rail weekend"), createdAt: .distantPast)
        var input = plan()
        input.end = nextDay
        input.startTime = LocalClock(rawValue: "23:10")
        input.endTime = LocalClock(rawValue: "06:30")
        let item = ItineraryItem(id: UUID().uuidString, tripID: trip.id, input: try input.validated(), createdAt: .distantPast)
        let days = ItineraryTimeline.days(for: [item])
        #expect(days.map(\.day) == [day, nextDay])
        #expect(days.flatMap(\.events).map(\.role) == [.departure, .arrival])
        #expect(days.flatMap(\.events).map(\.timeText) == ["23:10", "06:30"])
        #expect(Set(days.flatMap(\.events).map { $0.item.id }) == [item.id])
        #expect(ItinerarySummary(items: [item]).total == 1)
        #expect(ItinerarySummary(items: [item]).transport == 1)
        for text in ["train", "EXAMPLE paris", "st pancras", "TRAIN-42", "Bring tickets"] {
            #expect(ItineraryQuery(text: text, kind: .transport, bookingState: .booked).matching([item]) == [item])
        }
        #expect(ItineraryQuery(kind: .flight).matching([item]).isEmpty)
        let text = ItineraryText.make(trip: trip, items: [item], options: .init(includeNotes: true, includeReferences: true))
        #expect(text.contains("Transport: Train · Example Rail"))
        #expect(text.contains("Paris Gare du Nord → London St Pancras"))
        #expect(text.components(separatedBy: "TRAIN-42").count == 2)
        #expect(text.components(separatedBy: "Bring tickets").count == 2)
        let privateText = ItineraryText.make(trip: trip, items: [item])
        #expect(!privateText.contains("TRAIN-42") && !privateText.contains("Bring tickets"))
        var undated = input
        undated.start = nil; undated.end = nil; undated.startTime = nil; undated.endTime = nil
        let idea = ItineraryItem(id: UUID().uuidString, tripID: trip.id, input: undated, createdAt: .distantPast)
        #expect(ItineraryTimeline.days(for: [idea]).flatMap(\.events).map(\.role) == [.plan])
        #expect(ItineraryQuery(undatedOnly: true).matching([item, idea]) == [idea])
        input.end = day
        let sameDay = ItineraryItem(id: item.id, tripID: trip.id, input: input, createdAt: .distantPast)
        #expect(ItineraryTimeline.days(for: [sameDay]).flatMap(\.events).count == 2)
    }

    @Test func sharingBackupsRecoveryAndPermanentRemovalPreserveTransport() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try TripRepository(databaseURL: folder.appendingPathComponent("source.sqlite"))
        let trip = try await source.save(TripInput(name: "Transport QA", plannedTravelers: 3, budgetCents: 50_000), id: UUID().uuidString)
        let item = try await source.saveItem(plan(), id: UUID().uuidString, tripID: trip.id)
        let archive = try TripArchive.encode([trip], items: [item])
        #expect(try header(archive)["version"] as? Int == 5)
        let target = try TripRepository(databaseURL: folder.appendingPathComponent("target.sqlite"))
        #expect(try await target.restore(archive).items == [item])
        let package = try SharedTripPackage(trip: trip, items: [item])
        let encoded = try package.encoded()
        #expect(try header(encoded)["version"] as? Int == 2)
        let received = try await target.importSharedTrip(SharedTripPackage.decode(encoded))
        let copy = try #require(received.snapshot.items.first { $0.tripID == received.tripID })
        #expect(copy.input == item.input && copy.id != item.id)
        #expect(try await target.importSharedTrip(package).alreadyImported)
        let deleted = try await target.deleteTrip(id: received.tripID)
        #expect(!deleted.items.contains { $0.id == copy.id })
        let entry = try #require(deleted.deletedTrips.first)
        let restored = try await target.restoreDeletedTrip(id: entry.id)
        #expect(restored.snapshot.items.contains(copy))
        #expect(restored.snapshot.sharedTripImports[package.id] == received.tripID)
        let deletedAgain = try await target.deleteTrip(id: received.tripID)
        let purged = try await target.permanentlyDeleteTrip(id: #require(deletedAgain.deletedTrips.first).id)
        #expect(purged.deletedTrips.isEmpty && purged.items == [item])
        for (data, legacyVersion, isBackup) in [(archive, 4, true), (encoded, 1, false)] {
            var json = try header(data)
            json["version"] = legacyVersion
            let changed = try JSONSerialization.data(withJSONObject: json)
            if isBackup { #expect(throws: TripError.self) { try TripArchive.decode(changed) } }
            else { #expect(throws: TripError.self) { try SharedTripPackage.decode(changed) } }
        }
        // A future header is recognized even if its records use an unknown future kind.
        for format in ["travel-view-native", "travel-view-trip"] {
            let data = Data("{\"format\":\"\(format)\",\"version\":99,\"items\":[{\"kind\":\"future\"}]}".utf8)
            do {
                if format == "travel-view-native" { _ = try TripArchive.decode(data) }
                else { _ = try SharedTripPackage.decode(data) }
                Issue.record("A future format must be rejected")
            } catch { #expect(error.localizedDescription.contains("different version")) }
        }
        #expect(try header(TripArchive.encode([trip]))["version"] as? Int == 4)
        #expect(try header(SharedTripPackage(trip: trip, items: []).encoded())["version"] as? Int == 1)
    }

    @Test func upgradePreservesPreTransportRowsReceiptsAndLegacyRecovery() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("old.sqlite")
        let repository = try TripRepository(databaseURL: url)
        let trip = try await repository.save(TripInput(name: "Existing trip"), id: UUID().uuidString)
        let hotel = try await repository.saveItem(.init(kind: .lodging, title: "Hotel", start: day, end: nextDay,
            location: "London", notes: "Late arrival", startTime: LocalClock(rawValue: "16:00"),
            endTime: LocalClock(rawValue: "10:00"), bookingState: .booked, reservationReference: "STAY-9"),
            id: UUID().uuidString, tripID: trip.id)
        let flight = try await repository.saveItem(.init(kind: .flight, title: "Flight", flight: .init(number: "BA178")),
            id: UUID().uuidString, tripID: trip.id)
        let legacyTrip = try await repository.save(TripInput(name: "Old recovery"), id: UUID().uuidString)
        let legacyItem = try await repository.saveItem(.init(kind: .activity, title: "Museum"), id: UUID().uuidString, tripID: legacyTrip.id)
        let deleted = try await repository.deleteTrip(id: legacyTrip.id)
        let entry = try #require(deleted.deletedTrips.first)
        // Reproduce the preceding shipped table and its migration ledger, including a v1 recovery payload.
        try await repository.database.write { db in
            try db.execute(sql: """
                CREATE TABLE itineraryItems_old (
                    id TEXT PRIMARY KEY NOT NULL, tripID TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
                    kind TEXT NOT NULL CHECK (kind IN ('flight', 'lodging', 'activity')),
                    title TEXT NOT NULL, start TEXT, end TEXT, location TEXT NOT NULL, notes TEXT NOT NULL,
                    flight TEXT, createdAt DATETIME NOT NULL, startTime TEXT, endTime TEXT,
                    bookingState TEXT NOT NULL DEFAULT 'planned' CHECK (bookingState IN ('idea', 'planned', 'booked')),
                    reservationReference TEXT NOT NULL DEFAULT ''
                );
                INSERT INTO itineraryItems_old SELECT id, tripID, kind, title, start, end, location, notes, flight,
                    createdAt, startTime, endTime, bookingState, reservationReference FROM itineraryItems;
                DROP TABLE itineraryItems;
                ALTER TABLE itineraryItems_old RENAME TO itineraryItems;
                CREATE INDEX itineraryItems_tripID ON itineraryItems(tripID);
                DELETE FROM grdb_migrations WHERE identifier = 'addTransportPlans';
                """)
            let receipt = UUID().uuidString
            try db.execute(sql: "INSERT INTO sharedTripImports VALUES (?, ?)", arguments: [receipt, trip.id])
        }
        let upgraded = try TripRepository(databaseURL: url)
        let snapshot = try await upgraded.loadSnapshot()
        #expect(Set(snapshot.items.map(\.id)) == [hotel.id, flight.id])
        #expect(snapshot.items.contains(hotel) && snapshot.items.contains(flight))
        #expect(snapshot.sharedTripImports.values.contains(trip.id))
        let restored = try await upgraded.restoreDeletedTrip(id: entry.id)
        #expect(restored.snapshot.items.contains(legacyItem))
        _ = try await upgraded.saveItem(plan(), id: UUID().uuidString, tripID: trip.id)
        let removed = try await upgraded.deleteTrip(id: trip.id)
        #expect(!removed.items.contains { $0.tripID == trip.id })
        #expect(!removed.sharedTripImports.values.contains(trip.id))
        #expect(try await upgraded.database.read { db in try String.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty })
    }

    private func plan(mode: TransportMode = .train) -> ItineraryInput {
        ItineraryInput(kind: .transport, title: "Cross-channel train", start: day, end: day,
            notes: "Bring tickets", startTime: LocalClock(rawValue: "09:00"), endTime: LocalClock(rawValue: "10:30"),
            bookingState: .booked, reservationReference: " TRAIN-42 ",
            transport: .init(mode: mode, operatorName: " Example Rail ", departure: " Paris Gare du Nord ", arrival: " London St Pancras "))
    }
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func header(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
