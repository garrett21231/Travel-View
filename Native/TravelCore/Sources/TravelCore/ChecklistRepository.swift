import Foundation
import GRDB

extension TripRepository {
    public func saveChecklistItem(_ input: ChecklistInput, id: String, tripID: String,
                                  expectingExisting: Bool = false) async throws -> ChecklistItem {
        let input = try input.validated()
        let (id, tripID) = try Self.checklistIDs(id: id, tripID: tripID)
        let now = Date(timeIntervalSince1970: Date.now.timeIntervalSince1970.rounded(.down))
        return try await database.write { db in
            guard try Trip.exists(db, key: tripID) else { throw TripError("This trip is no longer available.") }
            let previous = try ChecklistItem.fetchOne(db, key: id)
            guard previous == nil || previous?.tripID == tripID else { throw TripError("This checklist item belongs to another trip.") }
            guard !expectingExisting || previous != nil else { throw TripError("This checklist item was removed. Close this editor to see the current checklist.") }
            let item = ChecklistItem(id: id, tripID: tripID, title: input.title,
                                     isCompleted: previous?.isCompleted ?? false, createdAt: previous?.createdAt ?? now)
            try item.save(db)
            return item
        }
    }

    public func setChecklistCompletion(id: String, tripID: String, completed: Bool) async throws -> ChecklistItem {
        let (id, tripID) = try Self.checklistIDs(id: id, tripID: tripID)
        return try await database.write { db in
            guard let current = try ChecklistItem.fetchOne(db, key: id), current.tripID == tripID else {
                throw TripError("This checklist item could not be found in the trip.")
            }
            let item = ChecklistItem(id: id, tripID: tripID, title: current.title,
                                     isCompleted: completed, createdAt: current.createdAt)
            try item.update(db)
            return item
        }
    }

    public func deleteChecklistItem(id: String, tripID: String) async throws {
        let (id, tripID) = try Self.checklistIDs(id: id, tripID: tripID)
        try await database.write { db in
            guard let item = try ChecklistItem.fetchOne(db, key: id), item.tripID == tripID else {
                throw TripError("This checklist item could not be found in the trip.")
            }
            try item.delete(db)
        }
    }

    private static func checklistIDs(id: String, tripID: String) throws -> (String, String) {
        guard let id = UUID(uuidString: id), let tripID = UUID(uuidString: tripID) else {
            throw TripError("The checklist identifier is invalid.")
        }
        return (id.uuidString, tripID.uuidString)
    }
}
