import Foundation

enum MeasurementKind: String, Codable {
    case forecast
    case observation

    var label: String {
        switch self {
        case .forecast: return "Forecast"
        case .observation: return "Observation"
        }
    }
}

/// One hourly record. `timestamp` is the START of the hour the values describe.
/// Provider semantics are documented in `EnvironmentalTimeSeries.intervalSemantics`.
struct EnvironmentalSample: Codable, Equatable {
    var timestamp: Date
    /// µg/m³
    var pm25: Double? = nil
    var usAQI: Double? = nil
    /// µg/m³
    var ozone: Double? = nil
    /// °C
    var temperatureC: Double? = nil
    /// °C — apparent temperature (heat index style)
    var apparentTemperatureC: Double? = nil
    /// %
    var relativeHumidity: Double? = nil
    var uvIndex: Double? = nil
    var precipitationProbability: Double? = nil
}

struct EnvironmentalTimeSeries: Codable, Equatable {
    var samples: [EnvironmentalSample]
    var source: String
    var kind: MeasurementKind
    var sourceUpdatedAt: Date? = nil
    var fetchedAt: Date
    var timeZoneIdentifier: String
    var intervalSemantics: String
    var attributionURL: String?
    var observedPM25Site: String? = nil
    var observationAttributionURL: String? = nil

    var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }

    var coveredRange: ClosedRange<Date>? {
        guard let first = samples.first?.timestamp, let last = samples.last?.timestamp else { return nil }
        return first...last.addingTimeInterval(3600)
    }
}

enum EnvironmentalDataError: LocalizedError {
    case network(underlying: String)
    case invalidLocation
    case malformedResponse
    case forecastUnavailable
    case outsideForecastRange
    case rateLimited
    case timedOut

    var errorDescription: String? {
        switch self {
        case .network(let underlying):
            return "Couldn't reach the environmental data service. (\(underlying))"
        case .invalidLocation:
            return "That location couldn't be found. Try a complete address or place name."
        case .malformedResponse:
            return "The environmental data service returned data this app couldn't read."
        case .forecastUnavailable:
            return "No forecast is currently published for this location."
        case .outsideForecastRange:
            return "Your activity window falls outside the published forecast range."
        case .rateLimited:
            return "The environmental data service is rate limiting requests. Try again shortly."
        case .timedOut:
            return "The request to the environmental data service timed out."
        }
    }
}
