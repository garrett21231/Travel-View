import Foundation
import GRDB

/// GRDB serializes writes and commits each change as a transaction.
public final class TripRepository: Sendable {
    let database: DatabaseQueue

    public init(databaseURL: URL) throws {
        try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        database = try DatabaseQueue(path: databaseURL.path, configuration: configuration)

        var migrator = DatabaseMigrator()
        migrator.registerMigration("createTrips") { db in
            try db.execute(sql: """
                CREATE TABLE trips (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    destinations TEXT NOT NULL,
                    start TEXT,
                    end TEXT,
                    plannedTravelers INTEGER NOT NULL CHECK (plannedTravelers BETWEEN 1 AND 999),
                    budgetCents INTEGER CHECK (budgetCents BETWEEN 0 AND 99999999999),
                    notes TEXT NOT NULL,
                    createdAt DATETIME NOT NULL,
                    CHECK ((start IS NULL AND end IS NULL) OR
                           (start IS NOT NULL AND end IS NOT NULL AND end >= start))
                )
                """)
        }
        migrator.registerMigration("createItineraryItems") { db in
            try db.execute(sql: """
                CREATE TABLE itineraryItems (
                    id TEXT PRIMARY KEY NOT NULL,
                    tripID TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
                    kind TEXT NOT NULL CHECK (kind IN ('flight', 'lodging', 'activity')),
                    title TEXT NOT NULL,
                    start TEXT,
                    end TEXT,
                    location TEXT NOT NULL,
                    notes TEXT NOT NULL,
                    flight TEXT,
                    createdAt DATETIME NOT NULL
                );
                CREATE INDEX itineraryItems_tripID ON itineraryItems(tripID);
                """)
        }
        try migrator.migrate(database)
    }

    public func load() async throws -> [Trip] {
        try await database.read { db in
            try Trip.order(Column("createdAt").desc, Column("id")).fetchAll(db)
        }
    }

    /// A stable ID makes retrying a save update the same trip.
    public func save(_ input: TripInput, id: String) async throws -> Trip {
        let input = try input.validated()
        guard let identifier = UUID(uuidString: id) else { throw TripError("The trip identifier is invalid.") }
        let id = identifier.uuidString
        let now = Date(timeIntervalSince1970: Date.now.timeIntervalSince1970.rounded(.down))
        return try await database.write { db in
            let previous = try Trip.fetchOne(db, key: id)
            let trip = Trip(id: id, input: input, createdAt: previous?.createdAt ?? now)
            try trip.save(db)
            return trip
        }
    }

    public struct ImportResult: Sendable {
        public let trips: [Trip]
        public let items: [ItineraryItem]
        public let added: Int
        public let addedItems: Int
    }

    /// Import is all-or-nothing. Existing IDs are preserved, so a retry is safe.
    public func restore(_ data: Data) async throws -> ImportResult {
        let incoming = try TripArchive.decode(data)
        return try await database.write { db in
            var added = 0
            for trip in incoming.trips {
                if try Trip.exists(db, key: trip.id) { continue }
                try trip.insert(db)
                added += 1
            }
            var addedItems = 0
            for item in incoming.items {
                if let existing = try ItineraryItem.fetchOne(db, key: item.id) {
                    guard existing.tripID == item.tripID else { throw TripError("An itinerary identifier belongs to another trip.") }
                    continue
                }
                try item.insert(db)
                addedItems += 1
            }
            return ImportResult(trips: try Trip.order(Column("createdAt").desc, Column("id")).fetchAll(db),
                                items: try ItineraryItem.fetchAll(db), added: added, addedItems: addedItems)
        }
    }
}
