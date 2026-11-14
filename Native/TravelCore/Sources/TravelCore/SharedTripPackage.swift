import Foundation

/// A complete, versioned snapshot of one trip. Its identity identifies this file, not a synchronized trip.
public struct SharedTripPackage: Identifiable, Sendable {
    public static let maximumBytes = TripArchive.maximumBytes
    public let id: String
    public let exportedAt: Date
    public let trip: Trip
    public let items: [ItineraryItem]

    private struct Envelope: Codable {
        let format: String
        let version: Int
        let id: String
        let exportedAt: Date
        let trip: Trip
        let items: [ItineraryItem]
    }

    public init(trip: Trip, items: [ItineraryItem]) throws {
        let contents = try TripArchive.validated(trips: [trip], items: items.filter { $0.tripID == trip.id })
        id = UUID().uuidString
        exportedAt = Date(timeIntervalSince1970: Date.now.timeIntervalSince1970.rounded(.down))
        self.trip = contents.trips[0]
        self.items = ItineraryItem.ordered(contents.items)
    }

    private init(id: String, exportedAt: Date, trip: Trip, items: [ItineraryItem]) {
        self.id = id; self.exportedAt = exportedAt; self.trip = trip; self.items = items
    }

    public func encoded() throws -> Data {
        let envelope = Envelope(format: "travel-view-trip", version: 1, id: id, exportedAt: exportedAt, trip: trip, items: items)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(envelope)
        guard data.count <= Self.maximumBytes else { throw TripError("This trip file exceeds the 10 MB limit.") }
        return data
    }

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumBytes else { throw TripError("Choose a trip file smaller than 10 MB.") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope: Envelope
        do { envelope = try decoder.decode(Envelope.self, from: data) }
        catch { throw TripError("This file could not be read as a shared Travel View trip.") }
        guard envelope.format == "travel-view-trip", envelope.version == 1 else {
            throw TripError("This trip file needs a different version of Travel View.")
        }
        guard let id = UUID(uuidString: envelope.id), envelope.exportedAt.timeIntervalSince1970.isFinite else {
            throw TripError("This trip file has an invalid identifier or export date.")
        }
        let contents = try TripArchive.validated(trips: [envelope.trip], items: envelope.items)
        return Self(id: id.uuidString, exportedAt: envelope.exportedAt, trip: contents.trips[0], items: ItineraryItem.ordered(contents.items))
    }
}
