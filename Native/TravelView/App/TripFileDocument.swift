import SwiftUI
import UniformTypeIdentifiers
import TravelCore

extension UTType {
    static let travelViewTrip = UTType(exportedAs: "local.travelview.trip", conformingTo: .json)
}

/// A file attachment usable by Files, Finder, AirDrop and other system sharing services.
struct TripFileDocument: FileDocument, Transferable, Sendable {
    static var readableContentTypes: [UTType] { [.travelViewTrip] }
    static var writableContentTypes: [UTType] { [.travelViewTrip] }
    let data: Data
    let package: SharedTripPackage
    var packageID: String { package.id }

    init(package: SharedTripPackage) throws { data = try package.encoded(); self.package = package }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        let package = try SharedTripPackage.decode(data)
        self.data = data; self.package = package
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .travelViewTrip) { document in
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("TravelViewSharedTrips", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            // Keep active transfers available; remove our own old temporary attachments on a later share.
            for old in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
                if UUID(uuidString: old.lastPathComponent) != nil,
                   let modified = try? old.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   modified < Date.now.addingTimeInterval(-86_400) { try? FileManager.default.removeItem(at: old) }
            }
            let folder = root.appendingPathComponent(document.packageID, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("Travel View Trip.travelview")
            try document.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

enum TripFileReader {
    /// File-size metadata is only a hint. The bounded read also rejects a larger actual file.
    static func read(_ url: URL) throws -> Data {
        guard url.isFileURL else { throw TripError("Open a shared trip file from Files or Finder.") }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: min(65_536, SharedTripPackage.maximumBytes + 1 - data.count)), !chunk.isEmpty {
            try Task.checkCancellation()
            data.append(chunk)
            guard data.count <= SharedTripPackage.maximumBytes else { throw TripError("Choose a trip file smaller than 10 MB.") }
        }
        return data
    }
}
