import Foundation

/// An airport's wall-clock date and time. It is never converted to the device's zone.
public struct LocalMoment: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    public let rawValue: String
    public init?(rawValue: String) {
        guard rawValue.count == 16, rawValue.dropFirst(10).first == "T",
              TravelDay(rawValue: String(rawValue.prefix(10))) != nil else { return nil }
        let clock = rawValue.suffix(5).split(separator: ":", omittingEmptySubsequences: false)
        guard clock.count == 2, clock.allSatisfy({ $0.count == 2 }),
              let hour = Int(clock[0]), let minute = Int(clock[1]),
              (0...23).contains(hour), (0...59).contains(minute),
              String(format: "%02d:%02d", hour, minute) == rawValue.suffix(5) else { return nil }
        self.rawValue = rawValue
    }

    public var day: TravelDay { TravelDay(rawValue: String(rawValue.prefix(10)))! }
    public var clock: String { String(rawValue.suffix(5)) }
    public var formatted: String { "\(day.formatted), \(clock)" }
    public static var pickerTimeZone: TimeZone { TimeZone(secondsFromGMT: 0)! }

    /// UTC is only a neutral carrier for DatePicker components, not the flight's zone.
    public var pickerDate: Date {
        let parts = clock.split(separator: ":").map { Int($0)! }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.pickerTimeZone
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0,
                             of: day.date(in: Self.pickerTimeZone))!
    }

    public init(day: TravelDay, clockFrom date: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.pickerTimeZone
        rawValue = day.rawValue + String(format: "T%02d:%02d", calendar.component(.hour, from: date),
                                         calendar.component(.minute, from: date))
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let moment = Self(rawValue: try container.decode(String.self)) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid local date and time.")
        }
        self = moment
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
