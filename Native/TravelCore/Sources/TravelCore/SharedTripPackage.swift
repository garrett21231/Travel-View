import Foundation

/// A complete, versioned snapshot of one trip. Its identity identifies this file, not a synchronized trip.
public struct SharedTripPackage: Identifiable, Sendable {
    public static let maximumBytes = TripArchive.maximumBytes
    public let id: String
    public let exportedAt: Date
    public let trip: Trip
    public let items: [ItineraryItem]
    public let checklist: [ChecklistItem]

    private struct Envelope: Codable {
        let format: String
        let version: Int
        let id: String
        let exportedAt: Date
        let trip: Trip
        let items: [ItineraryItem]
        let checklist: [ChecklistItem]?
    }

    public init(trip: Trip, items: [ItineraryItem], checklist: [ChecklistItem] = []) throws {
        let contents = try TripArchive.validated(trips: [trip], items: items.filter { $0.tripID == trip.id },
                                                checklist: checklist.filter { $0.tripID == trip.id })
        id = UUID().uuidString
        exportedAt = Date(timeIntervalSince1970: Date.now.timeIntervalSince1970.rounded(.down))
        self.trip = contents.trips[0]
        self.items = ItineraryItem.ordered(contents.items)
        self.checklist = ChecklistItem.ordered(contents.checklist)
    }

    private init(id: String, exportedAt: Date, trip: Trip, items: [ItineraryItem], checklist: [ChecklistItem]) {
        self.id = id; self.exportedAt = exportedAt; self.trip = trip; self.items = items
        self.checklist = checklist
    }

    public func encoded() throws -> Data {
        // Use an earlier format when the file does not contain newer features.
        let version = !checklist.isEmpty ? 3 : items.contains { $0.kind == .transport } ? 2 : 1
        let envelope = Envelope(format: "travel-view-trip", version: version,
                                id: id, exportedAt: exportedAt, trip: trip, items: items, checklist: checklist.isEmpty ? nil : checklist)
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
        let header: TripFileHeader
        do { header = try decoder.decode(TripFileHeader.self, from: data) }
        catch { throw TripError("This file could not be read as a shared Travel View trip.") }
        guard header.format == "travel-view-trip", (1...3).contains(header.version) else {
            throw TripError("This trip file needs a different version of Travel View.")
        }
        let envelope: Envelope
        do { envelope = try decoder.decode(Envelope.self, from: data) }
        catch { throw TripError("This file could not be read as a shared Travel View trip.") }
        guard envelope.version >= 2 || !envelope.items.contains(where: { $0.kind == .transport }) else {
            throw TripError("This trip file needs a different version of Travel View.")
        }
        guard let id = UUID(uuidString: envelope.id), envelope.exportedAt.timeIntervalSince1970.isFinite else {
            throw TripError("This trip file has an invalid identifier or export date.")
        }
        guard envelope.version < 3 || envelope.checklist != nil,
              envelope.version >= 3 || (envelope.checklist ?? []).isEmpty else {
            throw TripError("This trip file has incomplete or incompatible checklist details.")
        }
        let contents = try TripArchive.validated(trips: [envelope.trip], items: envelope.items, checklist: envelope.checklist ?? [])
        return Self(id: id.uuidString, exportedAt: envelope.exportedAt, trip: contents.trips[0],
                    items: ItineraryItem.ordered(contents.items), checklist: ChecklistItem.ordered(contents.checklist))
    }
}
