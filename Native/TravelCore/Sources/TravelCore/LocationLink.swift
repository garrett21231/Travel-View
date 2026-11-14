import Foundation

/// Searches for the saved location text. Opening the URL is an explicit UI action.
public enum LocationLink {
    public static func mapsSearch(for text: String) -> URL? {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "maps.apple.com"
        components.path = "/"
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        // A literal + in an address should not become a space in a web query parser.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }
}
