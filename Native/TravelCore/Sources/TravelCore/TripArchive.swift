import Foundation

/// A portable snapshot. Its version can evolve independently of the SQLite schema.
public struct TripArchive: Codable, Sendable {
    public static let maximumBytes = 10 * 1024 * 1024
    let format: String
    let version: Int
    let exportedAt: Date
    let trips: [Trip]
    let items: [ItineraryItem]

    public static func encode(_ trips: [Trip], items: [ItineraryItem] = []) throws -> Data {
        let archive = Self(format: "travel-view-native", version: 2, exportedAt: .now, trips: trips, items: items)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(archive)
        guard data.count <= maximumBytes else { throw TripError("This backup exceeds the 10 MB limit.") }
        return data
    }

    private enum CodingKeys: String, CodingKey { case format, version, exportedAt, trips, items }

    private init(format: String, version: Int, exportedAt: Date, trips: [Trip], items: [ItineraryItem]) {
        self.format = format; self.version = version; self.exportedAt = exportedAt; self.trips = trips; self.items = items
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(String.self, forKey: .format)
        version = try container.decode(Int.self, forKey: .version)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        trips = try container.decode([Trip].self, forKey: .trips)
        // Version 1 backups predate itinerary records. Version 2 must include them.
        items = version == 1 ? [] : try container.decode([ItineraryItem].self, forKey: .items)
    }

    struct Contents { let trips: [Trip]; let items: [ItineraryItem] }

    static func decode(_ data: Data) throws -> Contents {
        guard data.count <= maximumBytes else { throw TripError("Choose a backup smaller than 10 MB.") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive: Self
        do { archive = try decoder.decode(Self.self, from: data) }
        catch { throw TripError("This file could not be read as a native Travel View backup.") }
        guard archive.format == "travel-view-native", (1...2).contains(archive.version) else {
            throw TripError("This backup format needs a different version of Travel View.")
        }
        guard archive.trips.count <= 5000 else { throw TripError("Import up to 5,000 trips at a time.") }
        let trips = try archive.trips.map { trip in
            guard let identifier = UUID(uuidString: trip.id), trip.createdAt.timeIntervalSince1970.isFinite else {
                throw TripError("The backup contains an invalid trip identifier or creation date.")
            }
            return Trip(id: identifier.uuidString, input: try trip.input.validated(), createdAt: trip.createdAt)
        }
        guard Set(trips.map(\.id)).count == trips.count else { throw TripError("The backup repeats a trip identifier.") }
        guard archive.items.count <= 25_000 else { throw TripError("Import up to 25,000 itinerary items at a time.") }
        let tripIDs = Set(trips.map(\.id))
        let items = try archive.items.map { item in
            guard let id = UUID(uuidString: item.id), let tripID = UUID(uuidString: item.tripID),
                  tripIDs.contains(tripID.uuidString), item.createdAt.timeIntervalSince1970.isFinite else {
                throw TripError("The backup contains an itinerary item without a valid trip.")
            }
            return ItineraryItem(id: id.uuidString, tripID: tripID.uuidString,
                                 input: try item.input.validated(), createdAt: item.createdAt)
        }
        guard Set(items.map(\.id)).count == items.count else { throw TripError("The backup repeats an itinerary identifier.") }
        return Contents(trips: trips, items: items)
    }
}
