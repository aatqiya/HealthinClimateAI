import Foundation

struct RouteRequest: Codable {
    var origin: ActivityLocation
    var destination: ActivityLocation
    var mode: TransportMode
}
protocol RouteProviding { func routes(for request: RouteRequest) async throws -> [RouteOption] }
enum IntegrationError: LocalizedError {
    case setupRequired, invalidResponse
    var errorDescription: String? { self == .setupRequired ? "Route planning needs service setup. You can still compare activity times." : "Routes couldn't be retrieved. Your activity can still be analyzed." }
}

/// An HTTPS backend holds Google credentials and calls Google Routes computeRoutes.
/// The app never embeds a server API key. See INTEGRATIONS.md for the contract.
struct GoogleRoutesService: RouteProviding {
    static var endpoint: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "RESILIO_ROUTES_ENDPOINT") as? String,
              let url = URL(string: raw), url.scheme == "https" else { return nil }
        return url
    }
    static var isConfigured: Bool { endpoint != nil }
    func routes(for request: RouteRequest) async throws -> [RouteOption] {
        guard let endpoint = Self.endpoint else { throw IntegrationError.setupRequired }
        var http = URLRequest(url: endpoint)
        http.httpMethod = "POST"; http.timeoutInterval = 20
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.httpBody = try JSONEncoder.appEncoder.encode(request)
        let (data, response) = try await URLSession.shared.data(for: http)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw IntegrationError.invalidResponse }
        var routes = try JSONDecoder.appDecoder.decode([RouteOption].self, from: data)
        routes = routes.filter { $0.durationMinutes > 0 && $0.distanceMeters >= 0 }
        for index in routes.indices {
            routes[index].origin = request.origin; routes[index].destination = request.destination
            routes[index].environmentalComparisonAvailable = false
        }
        return Array(routes.prefix(5))
    }
}

// Explicit connection contracts for future authenticated services; no fake OAuth state.
protocol AccountAuthenticating { func signIn() async throws -> String; func signOut() async throws }
protocol ExternalCalendarConnecting {
    var source: CalendarSource { get }
    func connect() async throws
    func disconnect() async throws
    func events(in range: ClosedRange<Date>) async throws -> [ActivityEvent]
}
protocol PlanAssisting { func extract(_ message: String, profiles: [UserProfile], now: Date) -> ParsedPlan }
