import Foundation
import GRDB

/// Only lightweight summaries load with the collection. Full deleted plans stay in the local database.
public struct DeletedTrip: Identifiable, Equatable, Sendable {
    public let id: String
    public let tripID: String
    public let name: String
    public let deletedAt: Date
    public let itemCount: Int
}

private struct DeletedTripContents: Codable {
    let version: Int
    let trip: Trip
    let items: [ItineraryItem]
    let sharedTripImports: [String: String]
}

extension TripRepository {
    /// Preserve the complete trip before cascading its active items and import receipts away.
    /// Both changes commit together; a failed deletion leaves the original collection intact.
    public func deleteTrip(id: String) async throws -> Snapshot {
        guard let identifier = UUID(uuidString: id) else { throw TripError("The trip identifier is invalid.") }
        return try await database.write { db in
            guard let trip = try Trip.fetchOne(db, key: identifier.uuidString) else {
                throw TripError("This trip is no longer in your collection.")
            }
            let items = try ItineraryItem.filter(Column("tripID") == trip.id).fetchAll(db)
            let rows = try Row.fetchAll(db, sql: "SELECT packageID, tripID FROM sharedTripImports WHERE tripID = ?", arguments: [trip.id])
            let receipts = Dictionary(uniqueKeysWithValues: rows.map { ($0["packageID"] as String, $0["tripID"] as String) })
            let contents = DeletedTripContents(version: 1, trip: trip, items: items, sharedTripImports: receipts)
            // This private database payload has no external-file size limit, so large saved trips remain deletable.
            let data = try JSONEncoder().encode(contents)
            let now = Date(timeIntervalSince1970: Date.now.timeIntervalSince1970.rounded(.down))
            try db.execute(sql: "INSERT INTO deletedTrips (id, tripID, name, deletedAt, itemCount, contents) VALUES (?, ?, ?, ?, ?, ?)",
                           arguments: [UUID().uuidString, trip.id, trip.name, now, items.count, data])
            try trip.delete(db)
            return try Self.snapshot(in: db)
        }
    }

    public struct TripRestoration: Sendable {
        public let tripID: String
        public let snapshot: Snapshot
    }

    /// Remove only the selected recovery entry, including its complete saved payload.
    /// Active trips and newer copies are independent, even if their original identity matches.
    public func permanentlyDeleteTrip(id: String) async throws -> Snapshot {
        guard let identifier = UUID(uuidString: id) else { throw TripError("The deleted trip identifier is invalid.") }
        return try await database.write { db in
            guard try Row.fetchOne(db, sql: "SELECT id FROM deletedTrips WHERE id = ?", arguments: [identifier.uuidString]) != nil else {
                throw TripError("This trip has already been restored or removed from Recently deleted.")
            }
            try db.execute(sql: "DELETE FROM deletedTrips WHERE id = ?", arguments: [identifier.uuidString])
            return try Self.snapshot(in: db)
        }
    }

    /// Restore original identities without overwriting any trip or item added since deletion.
    public func restoreDeletedTrip(id: String) async throws -> TripRestoration {
        guard let identifier = UUID(uuidString: id) else { throw TripError("The deleted trip identifier is invalid.") }
        return try await database.write { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT tripID, contents FROM deletedTrips WHERE id = ?", arguments: [identifier.uuidString]) else {
                throw TripError("This trip has already been restored or is no longer in Recently deleted.")
            }
            let contents: DeletedTripContents
            do { contents = try JSONDecoder().decode(DeletedTripContents.self, from: row["contents"] as Data) }
            catch { throw TripError("The deleted trip couldn’t be read. It has been kept in Recently deleted.") }
            guard contents.version == 1, contents.trip.id == row["tripID"] as String else {
                throw TripError("This deleted trip needs a different version of Travel View.")
            }
            guard contents.items.allSatisfy({ $0.tripID == contents.trip.id }),
                  contents.sharedTripImports.values.allSatisfy({ $0 == contents.trip.id }) else {
                throw TripError("The deleted trip has inconsistent saved details. It has been kept in Recently deleted.")
            }
            guard try !Trip.exists(db, key: contents.trip.id) else {
                throw TripError("A trip with this identity is already in your collection. Its current details have been kept.")
            }
            try contents.trip.insert(db)
            for item in contents.items { try item.insert(db) }
            for (packageID, tripID) in contents.sharedTripImports {
                // A file may have been imported again after deletion. Keep that newer receipt's destination.
                try db.execute(sql: "INSERT INTO sharedTripImports (packageID, tripID) VALUES (?, ?) ON CONFLICT(packageID) DO NOTHING",
                               arguments: [packageID, tripID])
            }
            try db.execute(sql: "DELETE FROM deletedTrips WHERE id = ?", arguments: [identifier.uuidString])
            return TripRestoration(tripID: contents.trip.id, snapshot: try Self.snapshot(in: db))
        }
    }
}
