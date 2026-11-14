import Foundation

public enum TransportMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case train, bus, ferry, rentalCar, airportTransfer
    public var id: Self { self }
    public var title: String {
        switch self {
        case .train: "Train"
        case .bus: "Bus"
        case .ferry: "Ferry"
        case .rentalCar: "Rental car"
        case .airportTransfer: "Airport transfer"
        }
    }
    public var symbol: String {
        switch self {
        case .train: "tram.fill"
        case .bus: "bus.fill"
        case .ferry: "ferry.fill"
        case .rentalCar, .airportTransfer: "car.fill"
        }
    }
}

/// Route details belong to one plan, even when departure and arrival appear on different days.
/// Times live in the item's start/end fields and are local to each stop, rather than UTC instants.
public struct TransportDetails: Codable, Equatable, Sendable {
    public var mode: TransportMode
    public var operatorName: String
    public var departure: String
    public var arrival: String

    public init(mode: TransportMode = .train, operatorName: String = "", departure: String = "", arrival: String = "") {
        self.mode = mode; self.operatorName = operatorName; self.departure = departure; self.arrival = arrival
    }

    public var routeText: String {
        "\(departure.isEmpty ? "Departure to be decided" : departure) → \(arrival.isEmpty ? "Arrival to be decided" : arrival)"
    }

    func validated() throws -> Self {
        var value = self
        value.operatorName = operatorName.trimmingCharacters(in: .whitespacesAndNewlines)
        value.departure = departure.trimmingCharacters(in: .whitespacesAndNewlines)
        value.arrival = arrival.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.operatorName.count <= 160, value.departure.count <= 300, value.arrival.count <= 300 else {
            throw TripError("Use up to 160 characters for the transport company and 300 for each location.")
        }
        return value
    }
}
