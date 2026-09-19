import Foundation
import Observation

@Observable @MainActor
final class EnvironmentStore {
    struct Cached { var series: EnvironmentalTimeSeries; var checkedAt: Date; var location: ActivityLocation }
    var current: Cached?
    var errorMessage: String?
    var isLoading = false
    var lastCheckedAt: Date?
    private let provider: EnvironmentalDataProviding
    private var requestID = UUID()
    init(provider: EnvironmentalDataProviding = ForecastRepository.shared) { self.provider = provider }
    func refresh(location: ActivityLocation, force: Bool = false) async {
        let id = UUID(); requestID = id; lastCheckedAt = Date()
        if let previous = current, previous.location != location { current = nil }
        isLoading = true
        defer { if requestID == id { isLoading = false } }
        do {
            let now = Date()
            let series = try await provider.fetchConditions(latitude: location.latitude, longitude: location.longitude, range: now...now.addingTimeInterval(3600))
            guard requestID == id else { return }
            current = .init(series: series, checkedAt: now, location: location); errorMessage = nil
        } catch {
            guard requestID == id else { return }
            errorMessage = current == nil ? "Couldn't load conditions. Check your connection and try again." : "Couldn't refresh. Showing the last available forecast."
        }
    }
}
