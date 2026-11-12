import Foundation
import GRDB

/// A local HH:mm clock reading. The plan's calendar day is stored separately.
public struct LocalClock: RawRepresentable, Codable, Hashable, Comparable, Sendable, DatabaseValueConvertible {
    public let rawValue: String

    public init?(rawValue: String) {
        guard rawValue.count == 5,
              rawValue.range(of: #"^(?:[01][0-9]|2[0-3]):[0-5][0-9]$"#, options: .regularExpression) != nil else { return nil }
        self.rawValue = rawValue
    }

    public init(pickerDate: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = LocalMoment.pickerTimeZone
        rawValue = String(format: "%02d:%02d", calendar.component(.hour, from: pickerDate), calendar.component(.minute, from: pickerDate))
    }

    /// The fixed date carries clock components to DatePicker without device-zone conversion.
    public var pickerDate: Date { LocalMoment(rawValue: "2026-01-01T" + rawValue)!.pickerDate }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let clock = Self(rawValue: try container.decode(String.self)) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid local clock time.")
        }
        self = clock
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
    public var databaseValue: DatabaseValue { rawValue.databaseValue }
    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> Self? {
        String.fromDatabaseValue(dbValue).flatMap(Self.init(rawValue:))
    }
}
