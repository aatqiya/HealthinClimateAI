import Foundation

/// Modeled ambient concentration-time exposure over an activity window.
/// This is NOT inhaled dose, internal dose, or any clinical risk estimate.
struct ExposureMetric: Equatable {
    var pollutant: Pollutant
    /// Concentration-time integral, e.g. µg·h/m³ for PM2.5.
    var exposure: Double
    /// Time-weighted mean concentration over the window.
    var meanConcentration: Double
    /// Fraction (0...1) of the activity window covered by usable data.
    var dataCoverage: Double

    enum Pollutant: String, Equatable {
        case pm25
        case ozone
        case heat

        var label: String {
            switch self {
            case .pm25: return "PM2.5"
            case .ozone: return "Ozone"
            case .heat: return "Heat"
            }
        }

        var concentrationUnit: String {
            switch self {
            case .pm25, .ozone: return "µg/m³"
            case .heat: return "°C apparent"
            }
        }

        var exposureUnit: String {
            switch self {
            case .pm25, .ozone: return "µg·h/m³"
            case .heat: return "°C·h"
            }
        }
    }
}

struct ExposureAssessment: Equatable {
    var start: Date
    var durationMinutes: Int
    var metrics: [ExposureMetric.Pollutant: ExposureMetric]

    var end: Date { start.addingTimeInterval(TimeInterval(durationMinutes * 60)) }
    func metric(_ pollutant: ExposureMetric.Pollutant) -> ExposureMetric? { metrics[pollutant] }
}

enum ExposureEngine {
    /// Minimum share of the window that must have data before a metric is reported.
    static let minimumCoverage = 0.75

    /// Time-weighted integration across hourly intervals.
    ///
    /// Assumption (surfaced in the UI): each hourly value is the mean for the
    /// hour beginning at its timestamp. Partial hours contribute only their
    /// actual overlap with the activity window — never a flat average of the
    /// touched hours.
    static func assess(
        series: EnvironmentalTimeSeries,
        start: Date,
        durationMinutes: Int
    ) -> ExposureAssessment {
        let end = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
        let windowSeconds = end.timeIntervalSince(start)
        guard windowSeconds > 0 else {
            return ExposureAssessment(start: start, durationMinutes: durationMinutes, metrics: [:])
        }

        var metrics: [ExposureMetric.Pollutant: ExposureMetric] = [:]
        for pollutant in [ExposureMetric.Pollutant.pm25, .ozone, .heat] {
            var weightedSum = 0.0      // value · seconds
            var coveredSeconds = 0.0

            for sample in series.samples {
                let sampleStart = sample.timestamp
                let sampleEnd = sampleStart.addingTimeInterval(3600)
                let overlapStart = max(sampleStart, start)
                let overlapEnd = min(sampleEnd, end)
                let overlap = overlapEnd.timeIntervalSince(overlapStart)
                guard overlap > 0, let value = value(of: pollutant, in: sample), value.isFinite, (pollutant == .heat || value >= 0) else { continue }

                weightedSum += value * overlap
                coveredSeconds += overlap
            }

            let coverage = coveredSeconds / windowSeconds
            guard coverage >= minimumCoverage, coveredSeconds > 0 else { continue }

            let mean = weightedSum / coveredSeconds
            // Integral over the covered portion, expressed in value·hours.
            let exposure = weightedSum / 3600.0
            metrics[pollutant] = ExposureMetric(
                pollutant: pollutant,
                exposure: exposure,
                meanConcentration: mean,
                dataCoverage: coverage
            )
        }

        return ExposureAssessment(start: start, durationMinutes: durationMinutes, metrics: metrics)
    }

    private static func value(of pollutant: ExposureMetric.Pollutant, in sample: EnvironmentalSample) -> Double? {
        switch pollutant {
        case .pm25: return sample.pm25
        case .ozone: return sample.ozone
        case .heat: return sample.apparentTemperatureC ?? sample.temperatureC
        }
    }
}
