import Foundation

/// Provider-reported US AQI only. Round once, then classify that displayed integer.
enum AQICategory: Int, CaseIterable, Codable, Identifiable {
    case good, moderate, sensitive, unhealthy, veryUnhealthy, hazardous
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .good: "Good"
        case .moderate: "Moderate"
        case .sensitive: "Unhealthy for Sensitive Groups"
        case .unhealthy: "Unhealthy"
        case .veryUnhealthy: "Very Unhealthy"
        case .hazardous: "Hazardous"
        }
    }
    var range: String {
        switch self {
        case .good: "0–50"
        case .moderate: "51–100"
        case .sensitive: "101–150"
        case .unhealthy: "151–200"
        case .veryUnhealthy: "201–300"
        case .hazardous: "301+"
        }
    }
    static func reading(_ value: Double?) -> Int? {
        guard let value, value.isFinite, value >= 0, value < Double(Int.max) else { return nil }
        return Int(value.rounded())
    }
    static func category(for value: Double?) -> AQICategory? {
        guard let value = reading(value) else { return nil }
        switch value {
        case ...50: return .good
        case ...100: return .moderate
        case ...150: return .sensitive
        case ...200: return .unhealthy
        case ...300: return .veryUnhealthy
        default: return .hazardous
        }
    }
}

struct AQIWindow: Equatable {
    var peak: Int? = nil
    var coveredSeconds: Double = 0
    var totalSeconds: Double = 0
    var category: AQICategory? { AQICategory.category(for: peak.map(Double.init)) }
    var isPartial: Bool { coveredSeconds + 0.01 < totalSeconds }
    static func assess(series: EnvironmentalTimeSeries, start: Date, end: Date) -> AQIWindow {
        guard end > start else { return AQIWindow() }
        var result = AQIWindow(totalSeconds: end.timeIntervalSince(start))
        var intervals: [(Date, Date)] = []
        for sample in series.samples {
            let lo = max(start, sample.timestamp), hi = min(end, sample.timestamp.addingTimeInterval(3600))
            guard hi > lo, let value = AQICategory.reading(sample.usAQI) else { continue }
            result.peak = max(result.peak ?? value, value)
            intervals.append((lo, hi))
        }
        // Union avoids inflating coverage if a provider repeats an hour.
        var cursor = start
        for (lo, hi) in intervals.sorted(by: { $0.0 < $1.0 }) {
            result.coveredSeconds += max(0, hi.timeIntervalSince(max(lo, cursor)))
            cursor = max(cursor, hi)
        }
        return result
    }
}

/// Saved with an analyzed plan, never reconstructed from today's forecast.
/// Optional on ExposureSnapshot for compatibility with earlier saved plans.
struct SavedEnvironmentalWindow: Codable, Equatable {
    var location: ActivityLocation
    var start: Date
    var end: Date
    var series: EnvironmentalTimeSeries
    init(location: ActivityLocation, start: Date, end: Date, series: EnvironmentalTimeSeries) {
        self.location = location; self.start = start; self.end = end
        self.series = series
        self.series.samples = series.samples.filter { $0.timestamp < end && $0.timestamp.addingTimeInterval(3600) > start }
    }
}

extension ActivityEvent {
    var savedAQI: AQIWindow {
        guard let window = analysis?.environmentalWindow,
              window.location.latitude == plan.location.latitude,
              window.location.longitude == plan.location.longitude,
              window.start == selectedStart, window.end == endTime else {
            return AQIWindow(totalSeconds: endTime.timeIntervalSince(selectedStart))
        }
        return AQIWindow.assess(series: window.series, start: selectedStart, end: endTime)
    }
}
