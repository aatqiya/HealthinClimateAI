import Foundation

enum AlternativeChange: Equatable { case timeShift(minutes: Int) }
struct Alternative: Identifiable, Equatable {
    let id = UUID()
    var change: AlternativeChange
    var assessment: ExposureAssessment
    var reductionPercentByPollutant: [ExposureMetric.Pollutant: Double]
    func reductionPercent(for pollutant: ExposureMetric.Pollutant) -> Double? { reductionPercentByPollutant[pollutant] }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}
struct CounterfactualResult {
    var original: ExposureAssessment
    var alternatives: [Alternative]
    var bestMeaningful: Alternative?
    var primaryPollutant: ExposureMetric.Pollutant?
    var hadCandidates: Bool
}
enum CounterfactualEngine {
    // A product threshold for displaying changes, not a clinical significance threshold.
    static let minimumMeaningfulDifferencePercent = 10.0
    static let candidateStepMinutes = 15.0
    static func evaluate(plan: ActivityPlan, series: EnvironmentalTimeSeries, now: Date = Date()) -> CounterfactualResult {
        let original = ExposureEngine.assess(series: series, start: plan.startTime, durationMinutes: plan.durationMinutes)
        // Celsius ratios depend on the arbitrary temperature scale. Never call them
        // percent exposure reductions. Particle comparisons require complete coverage.
        let primary: ExposureMetric.Pollutant? = original.metric(.pm25)?.dataCoverage ?? 0 >= 0.999 ? .pm25 : nil
        var starts: [Date] = []
        switch plan.constraints.timeFlexibility {
        case .fixed: break
        case .halfHour, .oneHour:
            let minutes = plan.constraints.timeFlexibility.minutes
            for offset in stride(from: -minutes, through: minutes, by: 15) where offset != 0 {
                starts.append(plan.startTime.addingTimeInterval(Double(offset * 60)))
            }
        case .flexible:
            if let earliest = plan.constraints.earliestStart, let latest = plan.constraints.latestStart, earliest <= latest, latest.timeIntervalSince(earliest) <= 86400 {
                var date = earliest
                while date <= latest {
                    if abs(date.timeIntervalSince(plan.startTime)) > 60 { starts.append(date) }
                    date = date.addingTimeInterval(candidateStepMinutes * 60)
                }
            }
        }
        var options = starts.filter { $0 >= now }.compactMap { start -> Alternative? in
            guard let primary, let baseline = original.metric(primary), baseline.exposure > 0 else { return nil }
            let assessment = ExposureEngine.assess(series: series, start: start, durationMinutes: plan.durationMinutes)
            guard let metric = assessment.metric(primary), metric.dataCoverage >= 0.999 else { return nil }
            let reduction = (baseline.exposure - metric.exposure) / baseline.exposure * 100
            guard reduction >= minimumMeaningfulDifferencePercent else { return nil }
            return Alternative(change: .timeShift(minutes: Int(start.timeIntervalSince(plan.startTime) / 60)), assessment: assessment, reductionPercentByPollutant: [primary: reduction])
        }
        options.sort {
            let left = $0.reductionPercent(for: .pm25) ?? 0, right = $1.reductionPercent(for: .pm25) ?? 0
            return abs(left - right) < 0.001 ? abs($0.assessment.start.timeIntervalSince(plan.startTime)) < abs($1.assessment.start.timeIntervalSince(plan.startTime)) : left > right
        }
        let useful = Array(options.prefix(5))
        return .init(original: original, alternatives: useful, bestMeaningful: useful.first, primaryPollutant: primary, hadCandidates: !starts.isEmpty)
    }
}
