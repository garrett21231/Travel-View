import Foundation
import GRDB

/// A trip's calendar day. Storage preserves the day when the device changes time zone.
public struct TravelDay: RawRepresentable, Codable, Hashable, Comparable, Sendable, DatabaseValueConvertible {
    public let rawValue: String

    public init?(rawValue: String) {
        let parts = rawValue.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), (1...9999).contains(year),
              let month = Int(parts[1]), let day = Int(parts[2]),
              let date = Self.calendar.date(from: DateComponents(year: year, month: month, day: day)),
              Self.calendar.component(.year, from: date) == year,
              Self.calendar.component(.month, from: date) == month,
              Self.calendar.component(.day, from: date) == day,
              rawValue == String(format: "%04d-%02d-%02d", year, month, day)
        else { return nil }
        self.rawValue = rawValue
    }

    public init(_ date: Date = .now, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        rawValue = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    /// Local noon is useful when exchanging a calendar day with a native DatePicker.
    public func date(in timeZone: TimeZone = .current) -> Date {
        let parts = rawValue.split(separator: "-").map { Int($0)! }
        var calendar = Self.calendar
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))!
    }

    public var formatted: String {
        let formatter = DateFormatter()
        formatter.calendar = Self.calendar
        formatter.timeZone = Self.calendar.timeZone
        formatter.dateStyle = .medium
        return formatter.string(from: date(in: Self.calendar.timeZone))
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let value = Self(rawValue: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid calendar day.")
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var databaseValue: DatabaseValue { rawValue.databaseValue }

    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> Self? {
        String.fromDatabaseValue(dbValue).flatMap(Self.init(rawValue:))
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
