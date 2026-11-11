import Foundation
import Testing
@testable import TravelCore

struct FlightServiceTests {
    @Test func clientUsesServiceContractAndRetainsAirportLocalTimes() async throws {
        let client = client("valid")
        let query = try FlightQuery(number: " ba 178 ", departureDay: TravelDay(rawValue: "2027-03-04")!)
        let results = try await client.lookup(query)
        #expect(results.count == 1)
        #expect(results[0].departure.local?.rawValue == "2027-03-04T19:30")
        #expect(results[0].arrival.local?.rawValue == "2027-03-05T07:20")
        #expect(results[0].departure.timeZone == "America/New_York")
        let details = FlightDetails(schedule: results[0])
        #expect(details.lastLookup == results[0])
    }

    @Test func unavailableEmptyMalformedAndWrongDateResponsesStayDistinct() async throws {
        let query = try FlightQuery(number: "BA178", departureDay: TravelDay(rawValue: "2027-03-04")!)
        #expect(try await client("empty").lookup(query).isEmpty)
        for scenario in ["busy", "unavailable", "malformed", "wrong-date"] {
            await #expect(throws: TripError.self) { try await client(scenario).lookup(query) }
        }
        let insecure = FlightService(baseURL: URL(string: "http://example.com")!)
        await #expect(throws: TripError.self) { try await insecure.lookup(query) }
    }

    private func client(_ scenario: String) -> FlightService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixtureProtocol.self]
        return FlightService(baseURL: URL(string: "https://fixture.invalid/\(scenario)")!, session: URLSession(configuration: config))
    }
}

/// Immutable, request-selected fixtures let tests run concurrently without shared mutable handlers.
private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        let status = path.contains("busy") ? 429 : path.contains("unavailable") ? 503 : 200
        let date = path.contains("wrong-date") ? "2027-03-03" : "2027-03-04"
        let flight = """
            {"number":"BA178","airline":"British Airways",
             "departure":{"airport":"JFK","local":"\(date)T19:30","timeZone":"America/New_York"},
             "arrival":{"airport":"LHR","local":"2027-03-05T07:20","timeZone":"Europe/London"},
             "status":"Unknown","provider":"AeroDataBox","fetchedAt":"2026-11-11T12:00:00Z"}
            """
        let body = path.contains("malformed") ? "broken" : path.contains("empty") ? "{\"version\":1,\"flights\":[]}" : "{\"version\":1,\"flights\":[\(flight),\(flight)]}"
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
