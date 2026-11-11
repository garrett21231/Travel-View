import Foundation

public struct FlightQuery: Equatable, Sendable {
    public let number: String
    public let departureDay: TravelDay
    public init(number: String, departureDay: TravelDay) throws {
        self.number = try Self.normalizedNumber(number)
        self.departureDay = departureDay
    }
    public static func normalizedNumber(_ text: String) throws -> String {
        let value = text.uppercased().filter { !$0.isWhitespace }
        guard value.range(of: #"^[A-Z0-9]{2,3}[0-9]{1,4}[A-Z]?$"#, options: .regularExpression) != nil,
              value.prefix(3).contains(where: { $0.isLetter }) else {
            throw TripError("Enter an airline code and flight number, such as BA178 or AA100.")
        }
        return value
    }
}

public struct FlightStop: Codable, Equatable, Sendable {
    public let airport: String
    public let local: LocalMoment?
    public let timeZone: String?
    public init(airport: String, local: LocalMoment? = nil, timeZone: String? = nil) {
        self.airport = airport; self.local = local; self.timeZone = timeZone
    }
}

/// A saved lookup is a dated snapshot, never a promise of live flight status.
public struct FlightSchedule: Codable, Equatable, Identifiable, Sendable {
    public let number: String
    public let airline: String
    public let departure: FlightStop
    public let arrival: FlightStop
    public let status: String
    public let provider: String
    public let fetchedAt: Date
    public var id: String {
        [number, departure.airport, departure.local?.rawValue ?? "", arrival.airport, arrival.local?.rawValue ?? ""].joined(separator: "|")
    }
    public init(number: String, airline: String, departure: FlightStop, arrival: FlightStop,
                status: String, provider: String, fetchedAt: Date) {
        self.number = number; self.airline = airline; self.departure = departure; self.arrival = arrival
        self.status = status; self.provider = provider; self.fetchedAt = fetchedAt
    }
    func validate() throws {
        _ = try FlightQuery.normalizedNumber(number)
        guard airline.count <= 160, provider.count <= 80, status.count <= 80,
              fetchedAt.timeIntervalSince1970.isFinite,
              [departure, arrival].allSatisfy({
                  $0.airport.range(of: #"^[A-Z0-9]{3,4}$"#, options: .regularExpression) != nil && ($0.timeZone?.count ?? 0) <= 100
              }) else { throw TripError("The flight service returned incomplete details. You can enter the flight manually.") }
    }
}

/// The app talks to our service. The provider credential belongs only on that server.
public struct FlightService: Sendable {
    public let baseURL: URL
    private let session: URLSession
    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL; self.session = session
    }
    public func lookup(_ query: FlightQuery) async throws -> [FlightSchedule] {
        guard baseURL.scheme == "https" ||
                (baseURL.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(baseURL.host ?? "")),
              baseURL.user == nil, baseURL.password == nil, baseURL.query == nil, baseURL.fragment == nil else {
            throw TripError("Use a secure flight service address.")
        }
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/flights"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "number", value: query.number),
                                URLQueryItem(name: "date", value: query.departureDay.rawValue)]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch {
            if Task.isCancelled { throw CancellationError() }
            throw TripError("The flight service couldn’t be reached. Check your connection or enter the flight manually.")
        }
        guard let response = response as? HTTPURLResponse else { throw TripError("The flight service sent an unreadable response.") }
        switch response.statusCode {
        case 200: break
        case 400: throw TripError("Check the flight number and departure date, then try again.")
        case 429: throw TripError("Flight lookup is busy. Wait a little before trying again.")
        case 503: throw TripError("Flight lookup is temporarily unavailable. You can enter the flight manually.")
        default: throw TripError("The flight service couldn’t complete this lookup. Try again later.")
        }
        guard data.count <= 1_000_000 else { throw TripError("The flight service response was too large.") }
        struct Envelope: Decodable { let version: Int; let flights: [FlightSchedule] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope: Envelope
        do { envelope = try decoder.decode(Envelope.self, from: data) }
        catch { throw TripError("The flight service sent details this version of Travel View can’t read.") }
        guard envelope.version == 1, envelope.flights.count <= 50 else { throw TripError("The flight service response is unsupported.") }
        for flight in envelope.flights {
            try flight.validate()
            guard flight.departure.local.map({ $0.day == query.departureDay }) ?? true else {
                throw TripError("The service returned a flight for a different departure date. Enter the flight manually.")
            }
        }
        var seen = Set<String>()
        return envelope.flights.filter { seen.insert($0.id).inserted }
    }
}
