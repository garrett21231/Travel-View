import Foundation
import GRDB

extension TripRepository {
    public struct SharedTripImportResult: Sendable {
        public let snapshot: Snapshot
        public let tripID: String
        public let alreadyImported: Bool
    }

    /// One transaction creates the independent copy and its receipt. Reopening a file preserves local edits.
    public func importSharedTrip(_ package: SharedTripPackage) async throws -> SharedTripImportResult {
        try await database.write { db in
            if let id = try String.fetchOne(db, sql: "SELECT tripID FROM sharedTripImports WHERE packageID = ?", arguments: [package.id]),
               try Trip.exists(db, key: id) {
                return SharedTripImportResult(snapshot: try Self.snapshot(in: db), tripID: id, alreadyImported: true)
            }
            let tripID = UUID().uuidString
            let trip = Trip(id: tripID, input: package.trip.input,
                            createdAt: Date(timeIntervalSince1970: Date.now.timeIntervalSince1970.rounded(.down)))
            try trip.insert(db)
            // Preserve the original ID ordering for plans whose dates, times and creation timestamps tie.
            let newIDs = package.items.map { _ in UUID().uuidString }.sorted()
            for (item, id) in zip(package.items.sorted { $0.id < $1.id }, newIDs) {
                try ItineraryItem(id: id, tripID: tripID, input: item.input, createdAt: item.createdAt).insert(db)
            }
            try db.execute(sql: "INSERT INTO sharedTripImports (packageID, tripID) VALUES (?, ?)", arguments: [package.id, tripID])
            return SharedTripImportResult(snapshot: try Self.snapshot(in: db), tripID: tripID, alreadyImported: false)
        }
    }
}
