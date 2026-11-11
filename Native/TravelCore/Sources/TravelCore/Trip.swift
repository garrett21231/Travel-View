import Foundation
import GRDB

public struct TripError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// The values a form submits. Validation lives here so every screen uses the same rules.
public struct TripInput: Equatable, Sendable {
    public var name: String
    public var destinations: [String]
    public var start: TravelDay?
    public var end: TravelDay?
    public var plannedTravelers: Int
    public var budgetCents: Int64?
    public var notes: String

    public init(name: String, destinations: [String] = [], start: TravelDay? = nil,
                end: TravelDay? = nil, plannedTravelers: Int = 1,
                budgetCents: Int64? = nil, notes: String = "") {
        self.name = name
        self.destinations = destinations
        self.start = start
        self.end = end
        self.plannedTravelers = plannedTravelers
        self.budgetCents = budgetCents
        self.notes = notes
    }

    public func validated() throws -> Self {
        var value = self
        value.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.destinations = destinations.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        value.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.name.isEmpty, value.name.count <= 100 else {
            throw TripError("Enter a trip name of up to 100 characters.")
        }
        guard value.destinations.count <= 20, value.destinations.allSatisfy({ $0.count <= 160 }) else {
            throw TripError("Add up to 20 destinations, each up to 160 characters.")
        }
        guard (start == nil && end == nil) || (start != nil && end != nil && end! >= start!) else {
            throw TripError("Choose both dates, with the return on or after departure.")
        }
        guard (1...999).contains(plannedTravelers) else { throw TripError("Choose 1–999 planned travelers.") }
        guard budgetCents.map({ (0...Money.maximumCents).contains($0) }) ?? true else {
            throw TripError("The budget is outside the supported range.")
        }
        guard value.notes.count <= 2000 else { throw TripError("Keep notes within 2,000 characters.") }
        return value
    }
}

public struct Trip: Identifiable, Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "trips"
    public let id: String
    public let name: String
    public let destinations: [String]
    public let start: TravelDay?
    public let end: TravelDay?
    public let plannedTravelers: Int
    public let budgetCents: Int64?
    public let notes: String
    public let createdAt: Date

    init(id: String, input: TripInput, createdAt: Date) {
        self.id = id
        name = input.name
        destinations = input.destinations
        start = input.start
        end = input.end
        plannedTravelers = input.plannedTravelers
        budgetCents = input.budgetCents
        notes = input.notes
        self.createdAt = createdAt
    }

    public var input: TripInput {
        TripInput(name: name, destinations: destinations, start: start, end: end,
                  plannedTravelers: plannedTravelers, budgetCents: budgetCents, notes: notes)
    }

    public var destinationText: String { destinations.isEmpty ? "Destination undecided" : destinations.joined(separator: " · ") }
    public var dateText: String {
        guard let start, let end else { return "Dates to be decided" }
        return "\(start.formatted) – \(end.formatted)"
    }

    public func isInProgress(on today: TravelDay) -> Bool {
        guard let start, let end else { return false }
        return start <= today && today <= end
    }

    public static func upcoming(_ trips: [Self], on today: TravelDay) -> [Self] {
        trips.filter { $0.end.map { $0 >= today } ?? true }.sorted {
            if $0.start != $1.start {
                guard let left = $0.start else { return false }
                guard let right = $1.start else { return true }
                return left < right
            }
            return ($0.createdAt, $0.id) < ($1.createdAt, $1.id)
        }
    }
}

/// Budgets use whole cents. Blank and an explicit zero remain distinct.
public enum Money {
    public static let maximumCents: Int64 = 99_999_999_999

    public static func parse(_ text: String) throws -> Int64? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return nil }
        guard value.range(of: #"^(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)(?:\.[0-9]{1,2})?$"#,
                          options: .regularExpression) != nil else {
            throw TripError("Enter a USD budget such as 1,250.50, with up to two decimal places.")
        }
        let parts = value.replacingOccurrences(of: ",", with: "").split(separator: ".")
        guard parts[0].count <= 9, let dollars = Int64(parts[0]) else { throw TripError("Use up to 9 dollar digits.") }
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        let cents = dollars * 100 + Int64(fraction.padding(toLength: 2, withPad: "0", startingAt: 0))!
        guard cents <= maximumCents else { throw TripError("The budget is too large.") }
        return cents
    }

    public static func formatted(_ cents: Int64) -> String {
        (Decimal(cents) / 100).formatted(.currency(code: "USD"))
    }

    public static func editable(_ cents: Int64?) -> String {
        guard let cents else { return "" }
        return "\(cents / 100).\(String(format: "%02lld", cents % 100))"
    }
}
