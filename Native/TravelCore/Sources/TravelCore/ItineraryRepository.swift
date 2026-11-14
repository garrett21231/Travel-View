import Foundation
import GRDB

extension TripRepository {
    public struct Snapshot: Sendable {
        public let trips: [Trip]
        public let items: [ItineraryItem]
        public let checklist: [ChecklistItem]
        public let sharedTripImports: [String: String]
        public let deletedTrips: [DeletedTrip]
    }

    /// Active plans, sharing receipts and recovery summaries come from the same database snapshot.
    public func loadSnapshot() async throws -> Snapshot {
        try await database.read { db in
            try Self.snapshot(in: db)
        }
    }

    static func snapshot(in db: Database) throws -> Snapshot {
        let receipts = try Row.fetchAll(db, sql: "SELECT packageID, tripID FROM sharedTripImports")
        let deleted = try Row.fetchAll(db, sql: "SELECT id, tripID, name, deletedAt, itemCount, checklistCount FROM deletedTrips ORDER BY deletedAt DESC, id")
        return Snapshot(trips: try Trip.order(Column("createdAt").desc, Column("id")).fetchAll(db),
                        items: try ItineraryItem.fetchAll(db),
                        checklist: try ChecklistItem.fetchAll(db),
                        sharedTripImports: Dictionary(uniqueKeysWithValues: receipts.map { ($0["packageID"] as String, $0["tripID"] as String) }),
                        deletedTrips: deleted.map { DeletedTrip(id: $0["id"], tripID: $0["tripID"], name: $0["name"],
                                                              deletedAt: $0["deletedAt"], itemCount: $0["itemCount"], checklistCount: $0["checklistCount"]) })
    }

    public func saveItem(_ input: ItineraryInput, id: String, tripID: String) async throws -> ItineraryItem {
        let input = try input.validated()
        guard let itemUUID = UUID(uuidString: id), let tripUUID = UUID(uuidString: tripID) else {
            throw TripError("The itinerary identifier is invalid.")
        }
        let id = itemUUID.uuidString
        let tripID = tripUUID.uuidString
        let now = Date(timeIntervalSince1970: Date.now.timeIntervalSince1970.rounded(.down))
        return try await database.write { db in
            guard try Trip.exists(db, key: tripID) else { throw TripError("Save the trip before adding itinerary items.") }
            let previous = try ItineraryItem.fetchOne(db, key: id)
            guard previous == nil || previous?.tripID == tripID else {
                throw TripError("This itinerary item belongs to another trip.")
            }
            let item = ItineraryItem(id: id, tripID: tripID, input: input, createdAt: previous?.createdAt ?? now)
            try item.save(db)
            return item
        }
    }

    /// Recheck the exact reviewed record inside the write transaction to prevent stale-review overwrites.
    public func applyFlightUpdate(_ update: FlightUpdate, selection: Set<FlightUpdate.Field>) async throws -> ItineraryItem {
        let input = try update.applying(selection)
        return try await database.write { db in
            guard let current = try ItineraryItem.fetchOne(db, key: update.base.id) else {
                throw TripError("This flight was removed. Close this review and return to the itinerary.")
            }
            guard current == update.base else {
                throw TripError("This flight changed while you were reviewing it. Close this review and check it again to keep the newer edits.")
            }
            let saved = ItineraryItem(id: current.id, tripID: current.tripID, input: input, createdAt: current.createdAt)
            try saved.save(db)
            return saved
        }
    }

    public func deleteItem(id: String, tripID: String) async throws {
        try await database.write { db in
            guard let item = try ItineraryItem.fetchOne(db, key: id), item.tripID == tripID else {
                throw TripError("This itinerary item could not be found in the trip.")
            }
            try item.delete(db)
        }
    }
}
