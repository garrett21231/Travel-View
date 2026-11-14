import Foundation
import GRDB
import Testing
@testable import TravelCore

struct ReservationTests {
    @Test func referencesAreTrimmedAndBoundedAndNeverDetermineBookingState() throws {
        let hotel = try ItineraryInput(kind: .lodging, title: "Hotel", reservationReference: "  HOTEL-42\n").validated()
        #expect(hotel.reservationReference == "HOTEL-42")
        #expect(hotel.bookingState == .planned)
        #expect(try ItineraryInput(kind: .activity, title: "Tour", bookingState: .idea,
                                   reservationReference: "TICKET").validated().bookingState == .idea)
        #expect(throws: TripError.self) {
            try ItineraryInput(kind: .activity, title: "Tour", reservationReference: String(repeating: "a", count: 81)).validated()
        }
        let flight = try ItineraryInput(kind: .flight, title: "Flight", flight: FlightDetails(number: "BA178", bookingReference: "  KEEP  ")).validated()
        #expect(flight.bookingState == .planned)
        #expect(flight.flight?.bookingReference == "KEEP")
        #expect(flight.reservationReference.isEmpty)
    }

    @Test func allKindsKeepTheirReservationDetailsAcrossEditsAndReopening() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("trips.sqlite")
        let repository = try TripRepository(databaseURL: url)
        let trip = try await repository.save(TripInput(name: "London"), id: UUID().uuidString)
        for kind in ItineraryKind.allCases {
            let input = ItineraryInput(kind: kind, title: kind.title, location: "London", notes: "Keep these notes",
                                       flight: kind == .flight ? FlightDetails(number: "BA178", bookingReference: "FLIGHT") : nil,
                                       bookingState: .booked, reservationReference: kind == .flight ? "" : "REF-42",
                                       transport: kind == .transport ? TransportDetails() : nil)
            let saved = try await repository.saveItem(input, id: UUID().uuidString, tripID: trip.id)
            let reopened = try TripRepository(databaseURL: url)
            let loaded = try #require(try await reopened.loadSnapshot().items.first { $0.id == saved.id })
            #expect(loaded == saved)
            #expect(loaded.confirmationReference == (kind == .flight ? "FLIGHT" : "REF-42"))
            var edit = loaded.input
            edit.bookingState = .idea
            edit.reservationReference = ""
            edit.flight?.bookingReference = ""
            let changed = try await repository.saveItem(edit, id: saved.id, tripID: trip.id)
            #expect(changed.id == saved.id && changed.createdAt == saved.createdAt)
            #expect(changed.confirmationReference.isEmpty && changed.bookingState == .idea)
            #expect(changed.notes == saved.notes && changed.location == saved.location)
            #expect(try await reopened.loadSnapshot().items.first { $0.id == saved.id } == changed)
        }
    }

    @Test func thePreviousDatabaseMigratesWithoutLosingTimesOrFlightReferences() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("old.sqlite")
        let fixture = try DatabaseQueue(path: url.path)
        let tripID = UUID().uuidString, hotelID = UUID().uuidString, flightID = UUID().uuidString
        let legacyFlight = String(decoding: try JSONEncoder().encode(FlightDetails(number: "BA178", bookingReference: "LEGACY")), as: UTF8.self)
        try await fixture.write { db in
            // Exact columns available before the reservation migration; no new record encoder is used.
            try db.execute(sql: """
                CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY);
                INSERT INTO grdb_migrations VALUES ('createTrips'), ('createItineraryItems'), ('addItineraryTimes');
                CREATE TABLE trips (id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL, destinations TEXT NOT NULL,
                    start TEXT, end TEXT, plannedTravelers INTEGER NOT NULL, budgetCents INTEGER, notes TEXT NOT NULL, createdAt DATETIME NOT NULL);
                CREATE TABLE itineraryItems (id TEXT PRIMARY KEY NOT NULL, tripID TEXT NOT NULL REFERENCES trips(id),
                    kind TEXT NOT NULL, title TEXT NOT NULL, start TEXT, end TEXT, location TEXT NOT NULL,
                    notes TEXT NOT NULL, flight TEXT, createdAt DATETIME NOT NULL, startTime TEXT, endTime TEXT);
                """)
            try Trip(id: tripID, input: TripInput(name: "Existing trip"), createdAt: .now).insert(db)
            try db.execute(sql: """
                INSERT INTO itineraryItems (id, tripID, kind, title, start, end, location, notes, createdAt, startTime, endTime)
                VALUES (?, ?, 'lodging', 'Hotel', '2027-03-05', '2027-03-08', 'London', 'Keep hotel notes', ?, '15:00', '11:00')
                """, arguments: [hotelID, tripID, Date.now])
            try db.execute(sql: """
                INSERT INTO itineraryItems (id, tripID, kind, title, start, location, notes, flight, createdAt)
                VALUES (?, ?, 'flight', 'Flight', '2027-03-04', '', '', ?, ?)
                """, arguments: [flightID, tripID, legacyFlight, Date.now])
        }
        let repository = try TripRepository(databaseURL: url)
        let items = try await repository.loadSnapshot().items
        #expect(items.count == 2)
        #expect(items.allSatisfy { $0.bookingState == .planned && $0.reservationReference.isEmpty })
        let hotel = try #require(items.first { $0.id == hotelID })
        #expect(hotel.startTime?.rawValue == "15:00" && hotel.endTime?.rawValue == "11:00")
        #expect(hotel.notes == "Keep hotel notes")
        #expect(items.first { $0.id == flightID }?.confirmationReference == "LEGACY")
        var edit = hotel.input
        edit.bookingState = .booked
        edit.reservationReference = "HOTEL-NEW"
        let saved = try await repository.saveItem(edit, id: hotelID, tripID: tripID)
        let reopened = try TripRepository(databaseURL: url)
        #expect(try await reopened.loadSnapshot().items.first { $0.id == hotelID } == saved)
    }

    @Test func version4BackupsKeepStatesAndReferencesAndReimportPreservesLocalEdits() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try TripRepository(databaseURL: directory.appendingPathComponent("source.sqlite"))
        let trip = try await source.save(TripInput(name: "London"), id: UUID().uuidString)
        let item = try await source.saveItem(ItineraryInput(kind: .activity, title: "Tour", bookingState: .booked,
                                                           reservationReference: "TICKET-42"), id: UUID().uuidString, tripID: trip.id)
        let backup = try TripArchive.encode([trip], items: [item])
        let json = try #require(JSONSerialization.jsonObject(with: backup) as? [String: Any])
        #expect(json["version"] as? Int == 4)
        let target = try TripRepository(databaseURL: directory.appendingPathComponent("target.sqlite"))
        #expect(try await target.restore(backup).items == [item])
        var edit = item.input
        edit.bookingState = .idea
        edit.reservationReference = "CHANGED"
        let changed = try await target.saveItem(edit, id: item.id, tripID: trip.id)
        let retry = try await target.restore(backup)
        #expect(retry.addedItems == 0 && retry.items == [changed])
    }

    @Test func olderBackupsDefaultToPlannedAndKeepLegacyFlightReferences() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try TripRepository(databaseURL: directory.appendingPathComponent("source.sqlite"))
        let trip = try await source.save(TripInput(name: "London"), id: UUID().uuidString)
        let flight = try await source.saveItem(ItineraryInput(kind: .flight, title: "Flight", flight: FlightDetails(number: "BA178", bookingReference: "OLD")),
                                               id: UUID().uuidString, tripID: trip.id)
        let hotel = try await source.saveItem(ItineraryInput(kind: .lodging, title: "Hotel", start: TravelDay(rawValue: "2027-03-05"),
                                                            startTime: LocalClock(rawValue: "15:00")), id: UUID().uuidString, tripID: trip.id)
        let backup = try TripArchive.encode([trip], items: [flight, hotel])
        for version in [2, 3] {
            var old = try #require(JSONSerialization.jsonObject(with: backup) as? [String: Any])
            old["version"] = version
            var items = try #require(old["items"] as? [[String: Any]])
            for index in items.indices {
                items[index].removeValue(forKey: "bookingState")
                items[index].removeValue(forKey: "reservationReference")
                if version == 2 {
                    items[index].removeValue(forKey: "startTime")
                    items[index].removeValue(forKey: "endTime")
                }
            }
            old["items"] = items
            let target = try TripRepository(databaseURL: directory.appendingPathComponent("v\(version).sqlite"))
            let restored = try await target.restore(JSONSerialization.data(withJSONObject: old)).items
            #expect(restored.allSatisfy { $0.bookingState == .planned && $0.reservationReference.isEmpty })
            #expect(restored.first { $0.id == flight.id }?.confirmationReference == "OLD")
            #expect(restored.first { $0.id == hotel.id }?.startTime?.rawValue == (version == 3 ? "15:00" : nil))
        }
    }

    @Test func invalidReservationFieldsRejectTheWholeImport() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try TripRepository(databaseURL: directory.appendingPathComponent("source.sqlite"))
        let trip = try await source.save(TripInput(name: "London"), id: UUID().uuidString)
        let item = try await source.saveItem(ItineraryInput(kind: .lodging, title: "Hotel"), id: UUID().uuidString, tripID: trip.id)
        let backup = try TripArchive.encode([trip], items: [item])
        let target = try TripRepository(databaseURL: directory.appendingPathComponent("target.sqlite"))
        for (field, value) in [("bookingState", "cancelled" as Any), ("bookingState", NSNull()),
                                ("reservationReference", NSNull()), ("reservationReference", String(repeating: "x", count: 81))] {
            var invalid = try #require(JSONSerialization.jsonObject(with: backup) as? [String: Any])
            var items = try #require(invalid["items"] as? [[String: Any]])
            items[0][field] = value
            invalid["items"] = items
            let data = try JSONSerialization.data(withJSONObject: invalid)
            await #expect(throws: TripError.self) { try await target.restore(data) }
            #expect(try await target.loadSnapshot().trips.isEmpty)
            #expect(try await target.loadSnapshot().items.isEmpty)
        }
    }

    @Test func mapsLinksKeepTheSavedQueryAndEscapePunctuation() throws {
        #expect(LocationLink.mapsSearch(for: " \n ") == nil)
        let address = "Café A+B & Co #2, London / https://example.com?x=y"
        let url = try #require(LocationLink.mapsSearch(for: " \(address)\n"))
        let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(parts.scheme == "https" && parts.host == "maps.apple.com" && parts.path == "/")
        #expect(parts.queryItems == [URLQueryItem(name: "q", value: address)])
        #expect(parts.fragment == nil)
        #expect(url.absoluteString.contains("%2B"))
    }

    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("ReservationTests-\(UUID().uuidString)") }
}
