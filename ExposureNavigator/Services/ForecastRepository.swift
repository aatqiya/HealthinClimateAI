import Foundation

/// Forecast requests are coalesced and reused for 15 minutes. A UI check does
/// not change retrieval or source timestamps. No health context enters this API.
actor ForecastRepository: EnvironmentalDataProviding {
    static let shared = ForecastRepository()
    private let provider: EnvironmentalDataProviding
    private var cache: [String: EnvironmentalTimeSeries] = [:]
    private var inFlight: [String: Task<EnvironmentalTimeSeries, Error>] = [:]
    init(provider: EnvironmentalDataProviding = MergedEnvironmentalProvider()) { self.provider = provider }
    func fetchConditions(latitude: Double, longitude: Double, range: ClosedRange<Date>) async throws -> EnvironmentalTimeSeries {
        let key = String(format: "%.4f,%.4f", latitude, longitude)
        if let hit = cache[key], Date().timeIntervalSince(hit.fetchedAt) < 900 { return hit }
        if let task = inFlight[key] { return try await task.value }
        let provider = provider
        let task = Task { try await provider.fetchConditions(latitude: latitude, longitude: longitude, range: range) }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        let series = try await task.value
        cache[key] = series
        return series
    }
}
