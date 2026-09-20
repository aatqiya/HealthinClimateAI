import Foundation

struct WeeklyDay: Identifiable {
    var start: Date
    var scheduledSeconds: Double = 0
    var categorySeconds = Array(repeating: 0.0, count: 6)
    var id: Date { start }
    var coveredSeconds: Double { categorySeconds.reduce(0, +) }
}
struct WeeklyContribution: Identifiable {
    var event: ActivityEvent
    var aqiSeconds: Double = 0
    var pm25Seconds: Double = 0
    var id: UUID { event.id }
}
struct WeeklyExposureSummary {
    var start: Date
    var end: Date
    var timeZone: TimeZone
    var days: [WeeklyDay]
    var contributions: [WeeklyContribution]
    var scheduledSeconds: Double = 0
    var categorySeconds = Array(repeating: 0.0, count: 6)
    var conflictSeconds: Double = 0
    var pm25Seconds: Double = 0
    var pm25Integral: Double = 0 // µg·h/m³, covered time only
    var coveredSeconds: Double { categorySeconds.reduce(0, +) }
    var missingSeconds: Double { max(0, scheduledSeconds - coveredSeconds) }
    var pm25Mean: Double? { pm25Seconds > 0 ? pm25Integral / (pm25Seconds / 3600) : nil }
    var insight: String {
        guard coveredSeconds > 0 else { return scheduledSeconds > 0 ? "Saved hourly estimates aren't available for this time yet." : "Your completed activities will bring this week into focus." }
        let index = categorySeconds.indices.max { categorySeconds[$0] < categorySeconds[$1] }!
        let percent = Int((categorySeconds[index] / coveredSeconds * 100).rounded())
        return "\(percent)% of covered time was in the \(AQICategory(rawValue: index)!.label) range."
    }
}

enum WeeklyExposureEngine {
    /// Today plus the six preceding calendar days in one reporting timezone.
    /// Sweep all event/hour/day boundaries; count each elapsed instant at most once.
    static func summarize(events: [ActivityEvent], profileID: UUID?, now: Date, timeZone: TimeZone) -> WeeklyExposureSummary {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -6, to: today)!
        let days = (0..<7).map { WeeklyDay(start: calendar.date(byAdding: .day, value: $0, to: start)!) }
        let events = events.filter { $0.profileID == profileID && $0.selectedStart < now && $0.endTime > start && $0.endTime > $0.selectedStart }.sorted { $0.id.uuidString < $1.id.uuidString }
        var result = WeeklyExposureSummary(start: start, end: now, timeZone: timeZone, days: days, contributions: events.map { WeeklyContribution(event: $0) })
        var boundaries: Set<Date> = [start, now]
        days.forEach { boundaries.insert($0.start) }
        for event in events {
            boundaries.insert(max(start, event.selectedStart)); boundaries.insert(min(now, event.endTime))
            if let window = event.analysis?.environmentalWindow {
                boundaries.insert(max(start, min(now, window.series.fetchedAt)))
                for sample in window.series.samples {
                    boundaries.insert(max(start, min(now, sample.timestamp)))
                    boundaries.insert(max(start, min(now, sample.timestamp.addingTimeInterval(3600))))
                }
            }
        }
        let points = boundaries.sorted()
        for (lo, hi) in zip(points, points.dropFirst()) where hi > lo {
            let active = events.indices.filter { events[$0].selectedStart <= lo && events[$0].endTime >= hi }
            guard let first = active.first else { continue }
            let seconds = hi.timeIntervalSince(lo)
            let day = days.lastIndex { $0.start <= lo }!
            result.scheduledSeconds += seconds; result.days[day].scheduledSeconds += seconds
            let location = events[first].plan.location
            // Conservative: distinct coordinates are a conflict, even for nearby venues.
            guard active.allSatisfy({ events[$0].plan.location.latitude == location.latitude && events[$0].plan.location.longitude == location.longitude }) else {
                result.conflictSeconds += seconds; continue
            }
            // At the same location, prefer the latest saved retrieval available before
            // this interval. UUID breaks ties deterministically; no averaging forecasts.
            let candidates = active.compactMap { index -> (Int, EnvironmentalTimeSeries, EnvironmentalSample)? in
                let event = events[index]
                guard let window = event.analysis?.environmentalWindow,
                      window.start == event.selectedStart, window.end == event.endTime,
                      window.location.latitude == location.latitude, window.location.longitude == location.longitude,
                      window.series.kind != .forecast || window.series.fetchedAt <= lo,
                      let sample = window.series.samples.filter({ $0.timestamp <= lo && $0.timestamp.addingTimeInterval(3600) >= hi }).sorted(by: { $0.timestamp > $1.timestamp }).first else { return nil }
                return (index, window.series, sample)
            }.sorted { lhs, rhs in
                if lhs.1.fetchedAt != rhs.1.fetchedAt { return lhs.1.fetchedAt > rhs.1.fetchedAt }
                return events[lhs.0].id.uuidString < events[rhs.0].id.uuidString
            }
            if let candidate = candidates.first(where: { AQICategory.category(for: $0.2.usAQI) != nil }), let category = AQICategory.category(for: candidate.2.usAQI) {
                result.categorySeconds[category.rawValue] += seconds
                result.days[day].categorySeconds[category.rawValue] += seconds
                result.contributions[candidate.0].aqiSeconds += seconds
            }
            if let candidate = candidates.first(where: { $0.2.pm25.map { $0.isFinite && $0 >= 0 } == true }), let pm25 = candidate.2.pm25 {
                result.pm25Seconds += seconds; result.pm25Integral += pm25 * seconds / 3600
                result.contributions[candidate.0].pm25Seconds += seconds
            }
        }
        return result
    }
}
