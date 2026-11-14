import Foundation

/// Read the version before decoding records that a newer app may have extended.
struct TripFileHeader: Decodable {
    let format: String
    let version: Int
}

/// A portable snapshot. Its version can evolve independently of the SQLite schema.
public struct TripArchive: Codable, Sendable {
    public static let maximumBytes = 10 * 1024 * 1024
    let format: String
    let version: Int
    let exportedAt: Date
    let trips: [Trip]
    let items: [ItineraryItem]
    let checklist: [ChecklistItem]

    public static func encode(_ trips: [Trip], items: [ItineraryItem] = [], checklist: [ChecklistItem] = []) throws -> Data {
        let version = !checklist.isEmpty ? 6 : items.contains { $0.kind == .transport } ? 5 : 4
        let archive = Self(format: "travel-view-native", version: version,
                           exportedAt: .now, trips: trips, items: items, checklist: checklist)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(archive)
        guard data.count <= maximumBytes else { throw TripError("This backup exceeds the 10 MB limit.") }
        return data
    }

    private enum CodingKeys: String, CodingKey { case format, version, exportedAt, trips, items, checklist }

    private init(format: String, version: Int, exportedAt: Date, trips: [Trip], items: [ItineraryItem], checklist: [ChecklistItem]) {
        self.format = format; self.version = version; self.exportedAt = exportedAt; self.trips = trips; self.items = items
        self.checklist = checklist
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(String.self, forKey: .format)
        version = try container.decode(Int.self, forKey: .version)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        trips = try container.decode([Trip].self, forKey: .trips)
        // Version 1 backups predate itinerary records. Version 2 must include them.
        items = version == 1 ? [] : try container.decode([ItineraryItem].self, forKey: .items)
        checklist = version >= 6 ? try container.decode([ChecklistItem].self, forKey: .checklist) :
            try container.decodeIfPresent([ChecklistItem].self, forKey: .checklist) ?? []
    }

    struct Contents { let trips: [Trip]; let items: [ItineraryItem]; let checklist: [ChecklistItem] }

    static func decode(_ data: Data) throws -> Contents {
        guard data.count <= maximumBytes else { throw TripError("Choose a backup smaller than 10 MB.") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let header: TripFileHeader
        do { header = try decoder.decode(TripFileHeader.self, from: data) }
        catch { throw TripError("This file could not be read as a native Travel View backup.") }
        guard header.format == "travel-view-native", (1...6).contains(header.version) else {
            throw TripError("This backup format needs a different version of Travel View.")
        }
        let archive: Self
        do { archive = try decoder.decode(Self.self, from: data) }
        catch { throw TripError("This file could not be read as a native Travel View backup.") }
        guard archive.version >= 5 || !archive.items.contains(where: { $0.kind == .transport }) else {
            throw TripError("This backup format needs a different version of Travel View.")
        }
        guard archive.version >= 6 || archive.checklist.isEmpty else {
            throw TripError("This backup format needs a different version of Travel View.")
        }
        return try validated(trips: archive.trips, items: archive.items, checklist: archive.checklist)
    }

    /// Backups and single-trip files use the same field and relationship checks.
    static func validated(trips incomingTrips: [Trip], items incomingItems: [ItineraryItem], checklist incomingChecklist: [ChecklistItem] = []) throws -> Contents {
        guard incomingTrips.count <= 5000 else { throw TripError("Import up to 5,000 trips at a time.") }
        let trips = try incomingTrips.map { trip in
            guard let identifier = UUID(uuidString: trip.id), trip.createdAt.timeIntervalSince1970.isFinite else {
                throw TripError("The backup contains an invalid trip identifier or creation date.")
            }
            return Trip(id: identifier.uuidString, input: try trip.input.validated(), createdAt: trip.createdAt)
        }
        guard Set(trips.map(\.id)).count == trips.count else { throw TripError("The backup repeats a trip identifier.") }
        guard incomingItems.count <= 25_000 else { throw TripError("Import up to 25,000 itinerary items at a time.") }
        let tripIDs = Set(trips.map(\.id))
        let items = try incomingItems.map { item in
            guard let id = UUID(uuidString: item.id), let tripID = UUID(uuidString: item.tripID),
                  tripIDs.contains(tripID.uuidString), item.createdAt.timeIntervalSince1970.isFinite else {
                throw TripError("The backup contains an itinerary item without a valid trip.")
            }
            return ItineraryItem(id: id.uuidString, tripID: tripID.uuidString,
                                 input: try item.input.validated(), createdAt: item.createdAt)
        }
        guard Set(items.map(\.id)).count == items.count else { throw TripError("The backup repeats an itinerary identifier.") }
        guard incomingChecklist.count <= 25_000 else { throw TripError("Import up to 25,000 checklist items at a time.") }
        let checklist = try incomingChecklist.map { item in
            guard let id = UUID(uuidString: item.id), let tripID = UUID(uuidString: item.tripID),
                  tripIDs.contains(tripID.uuidString), item.createdAt.timeIntervalSince1970.isFinite else {
                throw TripError("The file contains a checklist item without a valid trip.")
            }
            return ChecklistItem(id: id.uuidString, tripID: tripID.uuidString, title: try item.input.validated().title,
                                 isCompleted: item.isCompleted, createdAt: item.createdAt)
        }
        guard Set(checklist.map(\.id)).count == checklist.count else { throw TripError("The file repeats a checklist identifier.") }
        return Contents(trips: trips, items: items, checklist: checklist)
    }
}
