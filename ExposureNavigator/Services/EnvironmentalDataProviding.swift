import Foundation

protocol EnvironmentalDataProviding: Sendable {
    /// Fetch hourly conditions covering at least `range`.
    /// Implementations must never invent values for missing hours.
    func fetchConditions(
        latitude: Double,
        longitude: Double,
        range: ClosedRange<Date>
    ) async throws -> EnvironmentalTimeSeries
}
