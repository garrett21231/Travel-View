import Foundation
import Observation
import TravelCore

/// The UI reads this store. Storage operations finish before published trips change.
@MainActor
@Observable
final class TripStore {
    private(set) var trips: [Trip] = []
    private(set) var itinerary: [ItineraryItem] = []
    private(set) var isLoading = false
    private(set) var isWorking = false
    private(set) var loadError: String?
    private var repository: TripRepository?

    var canChangeTrips: Bool { repository != nil && !isLoading && !isWorking && loadError == nil }

    func load() async {
        guard !isLoading, !isWorking else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            if repository == nil {
                // Database creation and migrations run away from the UI's main actor.
                repository = try await Task.detached(priority: .userInitiated) {
                    let directory: URL
                    #if DEBUG
                    if let override = ProcessInfo.processInfo.environment["TRAVEL_VIEW_NATIVE_DATA_DIR"] {
                        directory = URL(fileURLWithPath: override, isDirectory: true)
                    } else {
                        directory = try Self.defaultDirectory()
                    }
                    #else
                    directory = try Self.defaultDirectory()
                    #endif
                    return try TripRepository(databaseURL: directory.appendingPathComponent("trips.sqlite"))
                }.value
            }
            let snapshot = try await repository!.loadSnapshot()
            trips = snapshot.trips
            itinerary = snapshot.items
            loadError = nil
        } catch {
            loadError = "Your saved trips couldn’t be opened. Try again or check that storage is available on this device."
            #if DEBUG
            print("Travel View load failed", error)
            #endif
        }
    }

    func save(_ input: TripInput, id: String) async throws -> Trip {
        guard canChangeTrips, let repository else { throw TripError("Please wait for your trips to finish loading.") }
        isWorking = true
        defer { isWorking = false }
        do {
            let saved = try await repository.save(input, id: id)
            if let index = trips.firstIndex(where: { $0.id == saved.id }) {
                trips[index] = saved
            } else {
                trips.insert(saved, at: 0)
            }
            return saved
        } catch let error as TripError {
            throw error
        } catch {
            #if DEBUG
            print("Travel View save failed", error)
            #endif
            throw TripError("The trip couldn’t be saved. Your draft is still here. Try saving again.")
        }
    }

    func items(for tripID: String) -> [ItineraryItem] {
        ItineraryItem.ordered(itinerary.filter { $0.tripID == tripID })
    }

    func saveItem(_ input: ItineraryInput, id: String, tripID: String) async throws {
        guard canChangeTrips, let repository else { throw TripError("Please wait for your trips to finish loading.") }
        isWorking = true
        defer { isWorking = false }
        do {
            let saved = try await repository.saveItem(input, id: id, tripID: tripID)
            if let index = itinerary.firstIndex(where: { $0.id == saved.id }) { itinerary[index] = saved }
            else { itinerary.append(saved) }
        } catch let error as TripError { throw error }
        catch { throw TripError("The itinerary item couldn’t be saved. Your draft is still here.") }
    }

    func deleteItem(_ item: ItineraryItem) async throws {
        guard canChangeTrips, let repository else { throw TripError("Please wait for your trips to finish loading.") }
        isWorking = true
        defer { isWorking = false }
        do {
            try await repository.deleteItem(id: item.id, tripID: item.tripID)
            itinerary.removeAll { $0.id == item.id }
        } catch let error as TripError { throw error }
        catch { throw TripError("The itinerary item couldn’t be removed. Try again.") }
    }

    func restore(_ data: Data) async throws -> TripRepository.ImportResult {
        guard canChangeTrips, let repository else { throw TripError("Please wait for your trips to finish loading.") }
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await repository.restore(data)
            trips = result.trips
            itinerary = result.items
            return result
        } catch let error as TripError {
            throw error
        } catch {
            #if DEBUG
            print("Travel View import failed", error)
            #endif
            throw TripError("The backup couldn’t be imported. Try again when storage is available.")
        }
    }

    nonisolated private static func defaultDirectory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
            .appendingPathComponent("Travel View Native", isDirectory: true)
    }
}
