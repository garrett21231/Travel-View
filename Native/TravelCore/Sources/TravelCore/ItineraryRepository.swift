import Foundation
import GRDB

extension TripRepository {
    public struct Snapshot: Sendable {
        public let trips: [Trip]
        public let items: [ItineraryItem]
    }

    /// Read both collections from the same database snapshot.
    public func loadSnapshot() async throws -> Snapshot {
        try await database.read { db in
            Snapshot(trips: try Trip.order(Column("createdAt").desc, Column("id")).fetchAll(db),
                     items: try ItineraryItem.fetchAll(db))
        }
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

    public func deleteItem(id: String, tripID: String) async throws {
        try await database.write { db in
            guard let item = try ItineraryItem.fetchOne(db, key: id), item.tripID == tripID else {
                throw TripError("This itinerary item could not be found in the trip.")
            }
            try item.delete(db)
        }
    }
}
