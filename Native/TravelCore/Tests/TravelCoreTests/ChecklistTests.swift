import Foundation
import GRDB
import Testing
@testable import TravelCore

struct ChecklistTests {
    @Test func titlesValidateAndEditsKeepNewerCheckmarksAndStableIdentities() async throws {
        for title in ["", " \n ", "Two\nlines", String(repeating: "a", count: 161)] {
            #expect(throws: TripError.self) { try ChecklistInput(title: title).validated() }
        }
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("trips.sqlite")
        let repository = try TripRepository(databaseURL: url)
        let trip = try await repository.save(.init(name: "Checklist"), id: UUID().uuidString)
        let other = try await repository.save(.init(name: "Other"), id: UUID().uuidString)
        let item = try await repository.saveChecklistItem(.init(title: " Pack chargers \n"), id: UUID().uuidString, tripID: trip.id)
        #expect(item.title == "Pack chargers" && !item.isCompleted)
        let checked = try await repository.setChecklistCompletion(id: item.id.lowercased(), tripID: trip.id, completed: true)
        let edited = try await repository.saveChecklistItem(.init(title: "Pack USB-C chargers"), id: item.id, tripID: trip.id, expectingExisting: true)
        #expect(edited.isCompleted && edited.id == item.id && edited.createdAt == item.createdAt)
        #expect(checked.createdAt == item.createdAt)
        let reopened = try TripRepository(databaseURL: url)
        #expect(try await reopened.loadSnapshot().checklist == [edited])
        await #expect(throws: TripError.self) { try await reopened.saveChecklistItem(item.input, id: item.id, tripID: other.id) }
        await #expect(throws: TripError.self) { try await reopened.setChecklistCompletion(id: item.id, tripID: other.id, completed: false) }
        await #expect(throws: TripError.self) { try await reopened.deleteChecklistItem(id: item.id, tripID: other.id) }
        await #expect(throws: TripError.self) { try await reopened.saveChecklistItem(item.input, id: "bad-id", tripID: trip.id) }
        try await reopened.deleteChecklistItem(id: item.id, tripID: trip.id)
        await #expect(throws: TripError.self) { try await reopened.saveChecklistItem(item.input, id: item.id, tripID: trip.id, expectingExisting: true) }
        await #expect(throws: TripError.self) { try await reopened.setChecklistCompletion(id: item.id, tripID: trip.id, completed: true) }
        #expect(try await reopened.loadSnapshot().checklist.isEmpty)
    }

    @Test func failedUpdatesAndDeletesKeepTheSavedChecklistAndCanRetry() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let (repository, trip, tasks, _) = try await fixture(folder)
        let item = tasks[0]
        try await repository.database.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_task_update BEFORE UPDATE ON checklistItems BEGIN SELECT RAISE(ABORT, 'test failure'); END")
        }
        await #expect(throws: (any Error).self) { try await repository.setChecklistCompletion(id: item.id, tripID: trip.id, completed: !item.isCompleted) }
        #expect(try await repository.loadSnapshot().checklist.contains(item))
        try await repository.database.write { db in
            try db.execute(sql: "DROP TRIGGER reject_task_update; CREATE TRIGGER reject_task_delete BEFORE DELETE ON checklistItems BEGIN SELECT RAISE(ABORT, 'test failure'); END")
        }
        await #expect(throws: (any Error).self) { try await repository.deleteChecklistItem(id: item.id, tripID: trip.id) }
        #expect(try await repository.loadSnapshot().checklist.contains(item))
        try await repository.database.write { db in try db.execute(sql: "DROP TRIGGER reject_task_delete") }
        try await repository.deleteChecklistItem(id: item.id, tripID: trip.id)
        #expect(try await repository.loadSnapshot().checklist.count == tasks.count - 1)
    }

    @Test func backupsRoundTripTasksAndRetriesKeepCurrentTitlesAndCompletion() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let (_, trip, tasks, plans) = try await fixture(folder)
        let data = try TripArchive.encode([trip], items: plans, checklist: tasks)
        #expect(try json(data)["version"] as? Int == 6)
        let target = try TripRepository(databaseURL: folder.appendingPathComponent("target.sqlite"))
        let result = try await target.restore(data)
        #expect(ChecklistItem.ordered(result.checklist) == tasks && result.addedChecklistItems == tasks.count)
        let edited = try await target.saveChecklistItem(.init(title: "Keep my own title"), id: tasks[0].id, tripID: trip.id, expectingExisting: true)
        let checked = try await target.setChecklistCompletion(id: edited.id, tripID: trip.id, completed: !edited.isCompleted)
        let retry = try await target.restore(data)
        #expect(retry.addedChecklistItems == 0 && retry.checklist.contains(checked))
        #expect(retry.items == plans && retry.trips == [trip])
        // A checklist-only trip still needs the current format, even without itinerary items.
        #expect(try json(TripArchive.encode([trip], checklist: tasks))["version"] as? Int == 6)
    }

    @Test func malformedChecklistFilesAreRejectedBeforeAnyRecordsAreImported() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let (_, trip, tasks, plans) = try await fixture(folder)
        let package = try SharedTripPackage(trip: trip, items: plans, checklist: tasks)
        for backup in [false, true] {
            let original = try backup ? TripArchive.encode([trip], items: plans, checklist: tasks) : package.encoded()
            for change in 0...7 {
                var object = try json(original)
                var checklist = try #require(object["checklist"] as? [[String: Any]])
                switch change {
                case 0: object.removeValue(forKey: "checklist")
                case 1: object["checklist"] = NSNull()
                case 2: checklist[0]["tripID"] = UUID().uuidString
                case 3: checklist[0]["id"] = "bad-id"
                case 4: checklist[0]["title"] = " "
                case 5: checklist[0]["isCompleted"] = "true"
                case 6: checklist.append(checklist[0])
                default: object["version"] = backup ? 5 : 2
                }
                if change >= 2 { object["checklist"] = checklist }
                let data = try JSONSerialization.data(withJSONObject: object)
                if backup { #expect(throws: TripError.self) { try TripArchive.decode(data) } }
                else { #expect(throws: TripError.self) { try SharedTripPackage.decode(data) } }
            }
        }
        #expect(throws: TripError.self) { try TripArchive.validated(trips: [trip], items: [], checklist: Array(repeating: tasks[0], count: 25_001)) }
    }

    @Test func sharedFilesMakeIndependentChecklistsAndReopeningKeepsLocalEdits() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let (_, trip, tasks, plans) = try await fixture(folder)
        let foreign = ChecklistItem(id: UUID().uuidString, tripID: UUID().uuidString, title: "Other trip secret", createdAt: .now)
        let package = try SharedTripPackage(trip: trip, items: plans, checklist: tasks + [foreign])
        let data = try package.encoded()
        #expect(try json(data)["version"] as? Int == 3)
        let decoded = try SharedTripPackage.decode(data)
        #expect(decoded.checklist == tasks && !String(decoding: data, as: UTF8.self).contains(foreign.title))
        let target = try TripRepository(databaseURL: folder.appendingPathComponent("target.sqlite"))
        let imported = try await target.importSharedTrip(decoded)
        let copy = ChecklistItem.ordered(imported.snapshot.checklist)
        #expect(imported.tripID != trip.id && copy.map(\.title) == tasks.map(\.title))
        #expect(copy.map(\.isCompleted) == tasks.map(\.isCompleted))
        #expect(Set(copy.map(\.id)).isDisjoint(with: Set(tasks.map(\.id))))
        #expect(copy.allSatisfy { $0.tripID == imported.tripID })
        let edited = try await target.setChecklistCompletion(id: copy[0].id, tripID: imported.tripID, completed: !copy[0].isCompleted)
        let repeated = try await target.importSharedTrip(decoded)
        #expect(repeated.alreadyImported && repeated.snapshot.checklist.contains(edited))
        #expect(repeated.snapshot.checklist.count == tasks.count)
    }

    @Test func failedAndConcurrentSharedImportsKeepChecklistAndReceiptAtomic() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let (_, trip, tasks, plans) = try await fixture(folder)
        let package = try SharedTripPackage(trip: trip, items: plans, checklist: tasks)
        let target = try TripRepository(databaseURL: folder.appendingPathComponent("target.sqlite"))
        try await target.database.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_task_insert BEFORE INSERT ON checklistItems BEGIN SELECT RAISE(ABORT, 'test failure'); END")
        }
        await #expect(throws: (any Error).self) { try await target.importSharedTrip(package) }
        let failed = try await target.loadSnapshot()
        #expect(failed.trips.isEmpty && failed.items.isEmpty && failed.checklist.isEmpty && failed.sharedTripImports.isEmpty)
        try await target.database.write { db in try db.execute(sql: "DROP TRIGGER reject_task_insert") }
        async let first = target.importSharedTrip(package)
        async let second = target.importSharedTrip(package)
        let (left, right) = try await (first, second)
        #expect(left.tripID == right.tripID && left.alreadyImported != right.alreadyImported)
        #expect(try await target.loadSnapshot().checklist.count == tasks.count)
    }

    @Test func failedBackupImportAndConflictingParentsRollBackAllNewRecords() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let (_, trip, tasks, plans) = try await fixture(folder)
        let target = try TripRepository(databaseURL: folder.appendingPathComponent("target.sqlite"))
        let other = try await target.save(.init(name: "Existing trip"), id: UUID().uuidString)
        let existing = try await target.saveChecklistItem(.init(title: "Keep"), id: tasks[0].id, tripID: other.id)
        let data = try TripArchive.encode([trip], items: plans, checklist: tasks)
        await #expect(throws: TripError.self) { try await target.restore(data) }
        let after = try await target.loadSnapshot()
        #expect(after.trips == [other] && after.items.isEmpty && after.checklist == [existing])
    }

    @Test func tripRecoveryPreservesChecklistAndPurgeLeavesActiveCopiesAlone() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let (repository, trip, tasks, plans) = try await fixture(folder)
        let package = try SharedTripPackage(trip: trip, items: plans, checklist: tasks)
        let imported = try await repository.importSharedTrip(package)
        let copiedTasks = imported.snapshot.checklist.filter { $0.tripID == imported.tripID }
        let deleted = try await repository.deleteTrip(id: imported.tripID)
        let entry = try #require(deleted.deletedTrips.first)
        #expect(entry.checklistCount == tasks.count && entry.itemCount == plans.count)
        #expect(!deleted.checklist.contains { $0.tripID == imported.tripID })
        let restored = try await repository.restoreDeletedTrip(id: entry.id)
        #expect(Set(restored.snapshot.checklist.map(\.id)).isSuperset(of: Set(copiedTasks.map(\.id))))
        #expect(restored.snapshot.sharedTripImports[package.id] == imported.tripID)
        for task in copiedTasks { #expect(restored.snapshot.checklist.contains(task)) }
        let again = try await repository.deleteTrip(id: imported.tripID)
        let purged = try await repository.permanentlyDeleteTrip(id: #require(again.deletedTrips.first).id)
        #expect(purged.deletedTrips.isEmpty && ChecklistItem.ordered(purged.checklist) == tasks)
        let backup = try TripArchive.decode(TripArchive.encode(purged.trips, items: purged.items, checklist: purged.checklist))
        #expect(ChecklistItem.ordered(backup.checklist) == tasks)
    }

    @Test func deletionAndRestorationFailuresKeepWholeTripAndTasksRecoverable() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let (repository, trip, tasks, plans) = try await fixture(folder)
        try await repository.database.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_task_delete BEFORE DELETE ON checklistItems BEGIN SELECT RAISE(ABORT, 'test failure'); END")
        }
        await #expect(throws: (any Error).self) { try await repository.deleteTrip(id: trip.id) }
        let failedDelete = try await repository.loadSnapshot()
        #expect(failedDelete.trips == [trip] && failedDelete.items == plans && failedDelete.deletedTrips.isEmpty)
        #expect(ChecklistItem.ordered(failedDelete.checklist) == tasks)
        try await repository.database.write { db in
            try db.execute(sql: "DROP TRIGGER reject_task_delete; CREATE TRIGGER reject_task_insert BEFORE INSERT ON checklistItems BEGIN SELECT RAISE(ABORT, 'test failure'); END")
        }
        let deleted = try await repository.deleteTrip(id: trip.id)
        let entry = try #require(deleted.deletedTrips.first)
        await #expect(throws: (any Error).self) { try await repository.restoreDeletedTrip(id: entry.id) }
        let failedRestore = try await repository.loadSnapshot()
        #expect(failedRestore.trips.isEmpty && failedRestore.items.isEmpty && failedRestore.checklist.isEmpty)
        #expect(failedRestore.deletedTrips == deleted.deletedTrips)
        try await repository.database.write { db in try db.execute(sql: "DROP TRIGGER reject_task_insert") }
        #expect(ChecklistItem.ordered(try await repository.restoreDeletedTrip(id: entry.id).snapshot.checklist) == tasks)
    }

    @Test func oldDatabaseFilesAndRecoveryRemainCompatible() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("trips.sqlite")
        let repository = try TripRepository(databaseURL: url)
        let trip = try await repository.save(.init(name: "Before checklists"), id: UUID().uuidString)
        let plan = try await repository.saveItem(.init(kind: .transport, title: "Train", transport: .init()), id: UUID().uuidString, tripID: trip.id)
        let deleted = try await repository.deleteTrip(id: trip.id)
        let entry = try #require(deleted.deletedTrips.first)
        try await repository.database.write { db in
            try db.execute(sql: "DROP TABLE checklistItems; ALTER TABLE deletedTrips DROP COLUMN checklistCount; DELETE FROM grdb_migrations WHERE identifier = 'createTripChecklists'")
        }
        let upgraded = try TripRepository(databaseURL: url)
        #expect(try await upgraded.loadSnapshot().deletedTrips.first?.checklistCount == 0)
        let restored = try await upgraded.restoreDeletedTrip(id: entry.id)
        #expect(restored.snapshot.trips == [trip] && restored.snapshot.items == [plan] && restored.snapshot.checklist.isEmpty)
        let task = try await upgraded.saveChecklistItem(.init(title: "New task"), id: UUID().uuidString, tripID: trip.id)
        #expect(try await upgraded.loadSnapshot().checklist == [task])
        for version in 1...5 {
            var object = try json(TripArchive.encode([trip], items: version >= 5 ? [plan] : []))
            object["version"] = version; object.removeValue(forKey: "checklist")
            let decoded = try TripArchive.decode(JSONSerialization.data(withJSONObject: object))
            #expect(decoded.checklist.isEmpty && decoded.trips == [trip])
        }
        for version in 1...2 {
            let package = try SharedTripPackage(trip: trip, items: version == 2 ? [plan] : [])
            #expect(try SharedTripPackage.decode(package.encoded()).checklist.isEmpty)
        }
    }

    @Test func readableItinerariesIncludeOnlyOptedInTripScopedChecklistItems() throws {
        let trip = Trip(id: UUID().uuidString, input: .init(name: "Packing", notes: "Private trip note"), createdAt: .distantPast)
        let task = ChecklistItem(id: "a", tripID: trip.id, title: "Pack chargers", isCompleted: true, createdAt: .distantPast)
        let open = ChecklistItem(id: "b", tripID: trip.id, title: "Book transfer", createdAt: .distantPast)
        let foreign = ChecklistItem(id: "c", tripID: "other", title: "Other trip secret", createdAt: .distantPast)
        let tasks = [foreign, open, task]
        let text = ItineraryText.make(trip: trip, items: [], checklist: tasks)
        #expect(!text.contains(task.title) && !text.contains(open.title))
        let included = ItineraryText.make(trip: trip, items: [], options: .init(includeChecklist: true), checklist: tasks)
        #expect(included.contains("- [x] Pack chargers") && included.contains("- [ ] Book transfer"))
        #expect(!included.contains(foreign.title) && !included.contains(trip.notes))
    }

    private func fixture(_ folder: URL) async throws -> (TripRepository, Trip, [ChecklistItem], [ItineraryItem]) {
        let repository = try TripRepository(databaseURL: folder.appendingPathComponent("trips.sqlite"))
        let trip = try await repository.save(.init(name: "Checklist trip"), id: UUID().uuidString)
        let plan = try await repository.saveItem(.init(kind: .activity, title: "City walk"), id: UUID().uuidString, tripID: trip.id)
        let first = try await repository.saveChecklistItem(.init(title: "Pack chargers"), id: UUID().uuidString, tripID: trip.id)
        let second = try await repository.saveChecklistItem(.init(title: "Book transfer"), id: UUID().uuidString, tripID: trip.id)
        let checked = try await repository.setChecklistCompletion(id: first.id, tripID: trip.id, completed: true)
        return (repository, trip, ChecklistItem.ordered([checked, second]), [plan])
    }
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("ChecklistTests-\(UUID().uuidString)") }
    private func json(_ data: Data) throws -> [String: Any] { try #require(JSONSerialization.jsonObject(with: data) as? [String: Any]) }
}
