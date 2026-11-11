import Foundation
import GRDB
import Testing
@testable import TravelCore

struct TravelCoreTests {
    @Test func calendarDaysValidateAndKeepTheirIdentityAcrossTimeZones() throws {
        #expect(TravelDay(rawValue: "2026-02-30") == nil)
        #expect(TravelDay(rawValue: "2026-2-03") == nil)
        let day = try #require(TravelDay(rawValue: "2026-11-11"))
        for offset in [-11, 0, 14] {
            let zone = try #require(TimeZone(secondsFromGMT: offset * 3600))
            #expect(TravelDay(day.date(in: zone), timeZone: zone) == day)
        }
        let encoded = try JSONEncoder().encode(day)
        #expect(String(data: encoded, encoding: .utf8) == "\"2026-11-11\"")
        #expect(try JSONDecoder().decode(TravelDay.self, from: encoded) == day)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(TravelDay.self, from: Data("\"2026-02-30\"".utf8))
        }
    }

    @Test func budgetsUseExactCentsAndKeepUnsetSeparateFromZero() throws {
        #expect(try Money.parse("") == nil)
        #expect(try Money.parse("0") == 0)
        #expect(try Money.parse("1,250.50") == 125050)
        #expect(try Money.parse("999999999.99") == Money.maximumCents)
        for value in ["12.345", "1,25", "-2", "1000000000", "NaN"] {
            #expect(throws: TripError.self) { try Money.parse(value) }
        }
    }

    @Test func persistenceEditingAndSaveRetriesPreserveTheTrip() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("trips.sqlite")
        let repository = try TripRepository(databaseURL: url)
        let id = UUID().uuidString
        let input = TripInput(name: "  Boston weekend  ", destinations: [" Boston ", "", "Cambridge"],
                              start: TravelDay(rawValue: "2026-12-01"), end: TravelDay(rawValue: "2026-12-04"),
                              plannedTravelers: 2, budgetCents: 0, notes: " Train at noon ")
        async let first = repository.save(input, id: id)
        async let retry = repository.save(input, id: id)
        let (saved, repeated) = try await (first, retry)
        #expect(saved == repeated)
        #expect(saved.name == "Boston weekend")
        #expect(saved.destinations == ["Boston", "Cambridge"])

        let reopened = try TripRepository(databaseURL: url)
        #expect(try await reopened.load() == [saved])
        var edited = input
        edited.name = "Boston with friends"
        let updated = try await reopened.save(edited, id: id)
        #expect(updated.id == saved.id)
        #expect(updated.createdAt == saved.createdAt)
        #expect(try await repository.load() == [updated])
    }

    @Test func upcomingIncludesActiveAndUndatedPlansAndKeepsPastTripsStored() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try TripRepository(databaseURL: directory.appendingPathComponent("trips.sqlite"))
        _ = try await repository.save(TripInput(name: "Past", start: TravelDay(rawValue: "2020-01-01"),
                                               end: TravelDay(rawValue: "2020-01-02")), id: UUID().uuidString)
        let active = try await repository.save(TripInput(name: "Active", start: TravelDay(rawValue: "2026-11-10"),
                                                        end: TravelDay(rawValue: "2026-11-11")), id: UUID().uuidString)
        let future = try await repository.save(TripInput(name: "Future", start: TravelDay(rawValue: "2027-01-01"),
                                                        end: TravelDay(rawValue: "2027-01-02")), id: UUID().uuidString)
        let open = try await repository.save(TripInput(name: "Open plan"), id: UUID().uuidString)
        let all = try await repository.load()
        let today = try #require(TravelDay(rawValue: "2026-11-11"))
        #expect(all.count == 4)
        #expect(Trip.upcoming(all, on: today) == [active, future, open])
        #expect(active.isInProgress(on: today))
    }

    @Test func backupsRoundTripAndRepeatedImportsPreserveCurrentEdits() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try TripRepository(databaseURL: directory.appendingPathComponent("source.sqlite"))
        let original = try await source.save(TripInput(name: "Montréal", destinations: ["Montréal"], budgetCents: 12345),
                                             id: UUID().uuidString)
        let data = try TripArchive.encode([original])
        let target = try TripRepository(databaseURL: directory.appendingPathComponent("target.sqlite"))
        let first = try await target.restore(data)
        #expect(first.added == 1)
        #expect(first.trips == [original])
        var edit = original.input
        edit.notes = "Edited after import"
        let saved = try await target.save(edit, id: original.id)
        let retry = try await target.restore(data)
        #expect(retry.added == 0)
        #expect(retry.trips == [saved])
    }

    @Test func midImportDatabaseFailureRollsBackEveryInsertedTripAndCanRetry() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try TripRepository(databaseURL: directory.appendingPathComponent("source.sqlite"))
        let first = try await source.save(TripInput(name: "Accept"), id: UUID().uuidString)
        let second = try await source.save(TripInput(name: "Reject"), id: UUID().uuidString)
        let data = try TripArchive.encode([first, second])
        let targetURL = directory.appendingPathComponent("target.sqlite")
        let target = try TripRepository(databaseURL: targetURL)
        let fixture = try DatabaseQueue(path: targetURL.path)
        try await fixture.write { db in
            try db.execute(sql: """
                CREATE TRIGGER reject_import BEFORE INSERT ON trips
                WHEN NEW.name = 'Reject' BEGIN SELECT RAISE(ABORT, 'Test failure'); END
                """)
        }
        await #expect(throws: (any Error).self) { try await target.restore(data) }
        #expect(try await target.load().isEmpty)
        try await fixture.write { db in try db.execute(sql: "DROP TRIGGER reject_import") }
        let result = try await target.restore(data)
        #expect(result.added == 2)
    }

    private func testDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("TravelCoreTests-\(UUID().uuidString)", isDirectory: true)
    }
}
