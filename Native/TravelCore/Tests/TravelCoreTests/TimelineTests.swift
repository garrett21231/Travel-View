import Foundation
import GRDB
import Testing
@testable import TravelCore

struct TimelineTests {
    @Test func localClocksValidateAndTimedPlansRequireMatchingDates() throws {
        for text in ["9:00", "24:00", "12:60", "09:30\n", "09:30:00"] { #expect(LocalClock(rawValue: text) == nil) }
        let midnight = clock("00:00")
        #expect(LocalClock(pickerDate: midnight.pickerDate) == midnight)
        #expect(try JSONDecoder().decode(LocalClock.self, from: JSONEncoder().encode(midnight)) == midnight)
        #expect(throws: TripError.self) {
            try ItineraryInput(kind: .activity, title: "Museum", startTime: self.clock("09:00")).validated()
        }
        #expect(throws: TripError.self) {
            try ItineraryInput(kind: .activity, title: "Museum", start: self.day("2027-03-04"),
                               end: self.day("2027-03-04"), startTime: self.clock("10:00"), endTime: self.clock("09:00")).validated()
        }
        let overnight = try ItineraryInput(kind: .activity, title: "Night tour", start: day("2027-03-04"),
                                          end: day("2027-03-05"), startTime: clock("23:30"), endTime: clock("01:00")).validated()
        #expect(overnight.endTime == clock("01:00"))
    }

    @Test func daysGroupFlightEndsStaysAndActivitiesAndPutOpenPlansLast() throws {
        let flight = item("flight", try ItineraryInput(kind: .flight, title: "Flight", flight: FlightDetails(number: "BA178",
                          departureLocal: LocalMoment(rawValue: "2027-03-04T19:30"), arrivalLocal: LocalMoment(rawValue: "2027-03-05T07:20"))).validated())
        let hotel = item("hotel", ItineraryInput(kind: .lodging, title: "Hotel", start: day("2027-03-05"),
                         end: day("2027-03-08"), startTime: clock("15:00"), endTime: clock("11:00")))
        let activity = item("activity", ItineraryInput(kind: .activity, title: "Museum", start: day("2027-03-05"),
                            end: day("2027-03-05"), startTime: clock("10:00"), endTime: clock("12:00")))
        let open = item("open", ItineraryInput(kind: .activity, title: "Choose a restaurant"))
        let groups = ItineraryTimeline.days(for: [open, hotel, activity, flight])
        #expect(groups.map(\.id) == ["2027-03-04", "2027-03-05", "2027-03-08", "undated"])
        #expect(groups[1].events.map(\.role) == [.arrival, .activity, .checkIn])
        #expect(groups[1].events[1].timeText == "10:00–12:00")
        #expect(groups[2].events[0].role == .checkOut)
        #expect(groups[3].events.map(\.item.id) == [open.id])
        #expect(groups.flatMap(\.events).filter { $0.item.id == flight.id }.map(\.item.id) == [flight.id, flight.id])
        #expect(Set(groups.flatMap(\.events).map(\.id)).count == 6)
    }

    @Test func dateLineFlightsAndMultiDayActivitiesKeepBothCalendarEnds() throws {
        let flight = item("flight", try ItineraryInput(kind: .flight, title: "Pacific", flight: FlightDetails(number: "NZ8",
                          departureLocal: LocalMoment(rawValue: "2027-03-05T09:30"), arrivalLocal: LocalMoment(rawValue: "2027-03-04T22:15"))).validated())
        let activity = item("festival", ItineraryInput(kind: .activity, title: "Festival", start: day("2027-03-05"), end: day("2027-03-07")))
        let groups = ItineraryTimeline.days(for: [activity, flight])
        #expect(groups.map(\.id) == ["2027-03-04", "2027-03-05", "2027-03-07"])
        #expect(groups[0].events[0].role == .arrival)
        #expect(groups[0].events[0].time?.rawValue == "22:15")
        #expect(groups[2].events[0].role == .activityEnd)
    }

    @Test func timedEntriesComeFirstAndTiesStayStableWhenInputOrderChanges() {
        let date = day("2027-03-05")
        let first = item("a", ItineraryInput(kind: .activity, title: "A", start: date, startTime: clock("09:00")))
        let second = item("b", ItineraryInput(kind: .activity, title: "B", start: date, startTime: clock("09:00")))
        let unknown = item("c", ItineraryInput(kind: .activity, title: "Open time", start: date))
        let sorted = ItineraryTimeline.days(for: [unknown, second, first])
        #expect(sorted[0].events.map(\.item.id) == [first.id, second.id, unknown.id])
        #expect(ItineraryTimeline.days(for: [first, unknown, second]) == sorted)
    }

    @Test func comingUpUsesTodayOrTheNextPlannedDayAndDoesNotPickUndatedPlans() {
        let past = item("past", ItineraryInput(kind: .activity, title: "Past", start: day("2027-03-04")))
        let today = item("today", ItineraryInput(kind: .activity, title: "Today", start: day("2027-03-05"), startTime: clock("00:00")))
        let future = item("future", ItineraryInput(kind: .activity, title: "Future", start: day("2027-03-08")))
        let open = item("open", ItineraryInput(kind: .activity, title: "Open"))
        let groups = ItineraryTimeline.days(for: [past, today, future, open])
        #expect(ItineraryTimeline.upcomingDay(in: groups, on: day("2027-03-05"))?.id == "2027-03-05")
        #expect(ItineraryTimeline.upcomingDay(in: groups, on: day("2027-03-06"))?.id == "2027-03-08")
        #expect(ItineraryTimeline.upcomingDay(in: groups, on: day("2027-03-09")) == nil)
        #expect(ItineraryTimeline.upcomingDay(in: [], on: day("2027-03-05")) == nil)
    }

    @Test func aVersion2DatabaseKeepsExistingItemsAndAddsNullableTimes() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("v2.sqlite")
        let fixture = try DatabaseQueue(path: url.path)
        let tripID = UUID().uuidString, itemID = UUID().uuidString
        try await fixture.write { db in
            try db.execute(sql: """
                CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY);
                INSERT INTO grdb_migrations VALUES ('createTrips'), ('createItineraryItems');
                CREATE TABLE trips (id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL, destinations TEXT NOT NULL,
                    start TEXT, end TEXT, plannedTravelers INTEGER NOT NULL, budgetCents INTEGER, notes TEXT NOT NULL, createdAt DATETIME NOT NULL);
                CREATE TABLE itineraryItems (id TEXT PRIMARY KEY NOT NULL, tripID TEXT NOT NULL REFERENCES trips(id),
                    kind TEXT NOT NULL, title TEXT NOT NULL, start TEXT, end TEXT, location TEXT NOT NULL,
                    notes TEXT NOT NULL, flight TEXT, createdAt DATETIME NOT NULL);
                """)
            try Trip(id: tripID, input: TripInput(name: "Existing trip"), createdAt: .now).insert(db)
            try db.execute(sql: """
                INSERT INTO itineraryItems (id, tripID, kind, title, start, end, location, notes, createdAt)
                VALUES (?, ?, 'activity', 'Existing museum', '2027-03-05', NULL, 'London', '', ?)
                """, arguments: [itemID, tripID, Date.now])
        }
        let repository = try TripRepository(databaseURL: url)
        let snapshot = try await repository.loadSnapshot()
        #expect(snapshot.items[0].id == itemID)
        #expect(snapshot.items[0].startTime == nil)
        var edited = snapshot.items[0].input
        edited.startTime = clock("09:30")
        let saved = try await repository.saveItem(edited, id: itemID, tripID: tripID)
        let reopened = try TripRepository(databaseURL: url)
        #expect(try await reopened.loadSnapshot().items == [saved])
    }

    @Test func newBackupsKeepTimesAndOlderVersion2ItemsImportWithoutThem() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try TripRepository(databaseURL: directory.appendingPathComponent("source.sqlite"))
        let trip = try await source.save(TripInput(name: "London"), id: UUID().uuidString)
        let timed = try await source.saveItem(ItineraryInput(kind: .activity, title: "Museum", start: day("2027-03-05"),
                                             end: day("2027-03-05"), startTime: clock("09:00"), endTime: clock("11:00")), id: UUID().uuidString, tripID: trip.id)
        let data = try TripArchive.encode([trip], items: [timed])
        let target = try TripRepository(databaseURL: directory.appendingPathComponent("target.sqlite"))
        #expect(try await target.restore(data).items == [timed])
        var old = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(old["version"] as? Int == 3)
        old["version"] = 2
        var items = try #require(old["items"] as? [[String: Any]])
        items[0].removeValue(forKey: "startTime")
        items[0].removeValue(forKey: "endTime")
        old["items"] = items
        let oldTarget = try TripRepository(databaseURL: directory.appendingPathComponent("old.sqlite"))
        let restored = try await oldTarget.restore(JSONSerialization.data(withJSONObject: old))
        #expect(restored.items[0].id == timed.id)
        #expect(restored.items[0].startTime == nil)
        #expect(restored.items[0].endTime == nil)
    }

    private func day(_ value: String) -> TravelDay { TravelDay(rawValue: value)! }
    private func clock(_ value: String) -> LocalClock { LocalClock(rawValue: value)! }
    private func item(_ id: String, _ input: ItineraryInput) -> ItineraryItem {
        ItineraryItem(id: id, tripID: "trip", input: input, createdAt: Date(timeIntervalSince1970: 1_700_000_000))
    }
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("TimelineTests-\(UUID().uuidString)") }
}
