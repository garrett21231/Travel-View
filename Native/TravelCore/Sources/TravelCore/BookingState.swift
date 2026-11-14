import Foundation
import GRDB

/// A user-controlled planning label. Provider flight status never changes it.
public enum BookingState: String, Codable, CaseIterable, Identifiable, Sendable, DatabaseValueConvertible {
    case idea, planned, booked
    public var id: Self { self }
    public var title: String { rawValue.capitalized }
    public var symbol: String {
        switch self {
        case .idea: "lightbulb"
        case .planned: "calendar"
        case .booked: "checkmark.seal"
        }
    }
}
