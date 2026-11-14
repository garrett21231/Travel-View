import Foundation
import GRDB

/// The editor changes the title only. Completion has its own write so an old draft cannot undo a checkmark.
public struct ChecklistInput: Equatable, Sendable {
    public var title: String
    public init(title: String) { self.title = title }

    public func validated() throws -> Self {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 160, title.rangeOfCharacter(from: .newlines) == nil else {
            throw TripError("Enter a checklist item on one line, using up to 160 characters.")
        }
        return Self(title: title)
    }
}

/// Trip-owned tasks have their own stable identities, separate from itinerary plans.
public struct ChecklistItem: Identifiable, Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "checklistItems"
    public let id: String
    public let tripID: String
    public let title: String
    public let isCompleted: Bool
    public let createdAt: Date

    init(id: String, tripID: String, title: String, isCompleted: Bool = false, createdAt: Date) {
        self.id = id; self.tripID = tripID; self.title = title
        self.isCompleted = isCompleted; self.createdAt = createdAt
    }

    public var input: ChecklistInput { ChecklistInput(title: title) }
    public static func ordered(_ items: [Self]) -> [Self] {
        // Checking a task does not move it away from the user's finger or keyboard focus.
        items.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }
}
