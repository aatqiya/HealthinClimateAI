import Foundation

actor CountingProvider: EnvironmentalDataProviding {
    var count = 0
    let series: EnvironmentalTimeSeries
    init(series: EnvironmentalTimeSeries) { self.series = series }
    func fetchConditions(latitude: Double, longitude: Double, range: ClosedRange<Date>) async throws -> EnvironmentalTimeSeries {
        count += 1
        try await Task.sleep(for: .milliseconds(30))
        return series
    }
}

@main
struct RegressionTests {
    static var passed = 0
    static func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        guard condition() else { fatalError("FAIL: \(label)") }
        passed += 1; print("PASS: \(label)")
    }
    static func series(_ samples: [EnvironmentalSample]) -> EnvironmentalTimeSeries {
        .init(samples: samples, source: "Synthetic regression fixture", kind: .forecast, fetchedAt: Date(), timeZoneIdentifier: "UTC", intervalSemantics: "hour start", attributionURL: nil)
    }
    static func main() async throws {
        let hour = Date(timeIntervalSince1970: 2_000_001_600)
        let location = ActivityLocation(name: "Test field", formattedAddress: "Test location", latitude: 40.76, longitude: -73.95, timeZoneIdentifier: "America/New_York")
        let profile = UserProfile(name: "Maya", relationship: .child, age: 12, medicalConditions: ["Asthma"], createdAt: hour, updatedAt: hour)
        var plan = ActivityPlan(profileID: profile.id, activityType: .sports, activityName: "Soccer", location: location, startTime: hour, durationMinutes: 90)
        let hourly = series((0..<30).map { EnvironmentalSample(timestamp: hour.addingTimeInterval(Double($0) * 3600), pm25: $0 == 0 ? 40 : 10, apparentTemperatureC: 28) })
        let partial = ExposureEngine.assess(series: hourly, start: hour.addingTimeInterval(1800), durationMinutes: 90).metric(.pm25)!
        check(abs(partial.exposure - 30) < 0.00001, "partial-hour integral uses actual overlap")
        check(abs(partial.meanConcentration - 20) < 0.00001, "partial-hour weighted mean")
        check(ExposureEngine.assess(series: hourly, start: hour, durationMinutes: 0).metrics.isEmpty, "zero-duration windows are rejected")
        check(CounterfactualEngine.evaluate(plan: plan, series: hourly, now: hour.addingTimeInterval(-1)).alternatives.isEmpty, "fixed plans never shift time")
        plan.constraints.timeFlexibility = .oneHour
        let flexible = CounterfactualEngine.evaluate(plan: plan, series: hourly, now: hour.addingTimeInterval(-3600))
        check(!flexible.alternatives.isEmpty, "real fixture reduction produces alternatives")
        check(flexible.alternatives.count <= 5, "at most five alternatives")
        check(flexible.alternatives.allSatisfy { abs($0.assessment.start.timeIntervalSince(plan.startTime)) <= 3600 && $0.assessment.durationMinutes == 90 }, "all alternatives respect time bounds and fixed duration")
        check(flexible.alternatives.allSatisfy { ($0.reductionPercent(for: .pm25) ?? 0) >= 10 }, "only meaningful particle reductions appear")
        plan.constraints = .init(timeFlexibility: .flexible, earliestStart: hour.addingTimeInterval(900), latestStart: hour.addingTimeInterval(3600))
        let custom = CounterfactualEngine.evaluate(plan: plan, series: hourly, now: hour)
        check(custom.alternatives.allSatisfy { $0.assessment.start >= plan.constraints.earliestStart! && $0.assessment.start <= plan.constraints.latestStart! }, "custom bounds enforced")
        let missing = series([EnvironmentalSample(timestamp: hour, pm25: 40), EnvironmentalSample(timestamp: hour.addingTimeInterval(3600), pm25: nil), EnvironmentalSample(timestamp: hour.addingTimeInterval(7200), pm25: 1)])
        plan.durationMinutes = 120
        check(CounterfactualEngine.evaluate(plan: plan, series: missing, now: hour).alternatives.isEmpty, "missing data cannot masquerade as an improvement")
        plan.durationMinutes = 90
        let heatOnly = series((0..<5).map { EnvironmentalSample(timestamp: hour.addingTimeInterval(Double($0) * 3600), apparentTemperatureC: $0 == 0 ? 30 : 10) })
        check(CounterfactualEngine.evaluate(plan: plan, series: heatOnly, now: hour).alternatives.isEmpty, "Celsius ratios never become exposure percentages")
        check(CounterfactualEngine.evaluate(plan: plan, series: hourly, now: hour.addingTimeInterval(86400)).alternatives.isEmpty, "past alternatives excluded")
        let unchanged = series((0..<5).map { EnvironmentalSample(timestamp: hour.addingTimeInterval(Double($0) * 3600), pm25: 10) })
        check(CounterfactualEngine.evaluate(plan: plan, series: unchanged, now: hour).alternatives.isEmpty, "flat forecast never manufactures a recommendation")
        let decodedProfile = try JSONDecoder.appDecoder.decode(UserProfile.self, from: JSONEncoder.appEncoder.encode(profile))
        check(decodedProfile == profile, "profile Codable round trip")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("resilio-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let profiles = ProfileStore(directory: directory)
        profiles.add(profile)
        let another = UserProfile(name: "Me", relationship: .myself)
        profiles.add(another)
        let events = EventStore(directory: directory)
        var event = ActivityEvent(plan: plan, selectedStart: hour, selectedRoute: nil, analysis: nil)
        check(events.save(event), "event saved")
        profiles.select(another.id)
        check(events.events[0].profileID == profile.id, "profile switching preserves event ownership")
        event.selectedStart = hour.addingTimeInterval(3600)
        check(events.save(event) && events.events.count == 1, "re-analysis updates one existing event")
        check(events.events[0].plan.startTime == hour, "original baseline remains separate from chosen start")
        check(EventStore(directory: directory).events[0].selectedStart == event.selectedStart, "events persist across relaunch")
        let encodedEvent = try JSONEncoder.appEncoder.encode(event)
        check(!String(data: encodedEvent, encoding: .utf8)!.contains("Asthma"), "events do not duplicate health details")
        check(events.deleteEvents(for: profile.id) && events.events.isEmpty, "profile-related deletion removes its events")
        var tags: [String] = []
        tags = ProfileTags.adding("  Asthma ", to: tags)
        tags = ProfileTags.adding("asthma", to: tags)
        check(tags == ["Asthma"], "tags trim whitespace and prevent case-insensitive duplicates")
        tags = ProfileTags.adding("My custom condition", to: tags)
        check(tags.count == 2, "custom tags are supported")
        for index in 0..<30 { tags = ProfileTags.adding("Entry \(index)", to: tags) }
        check(tags.count == 25, "tags stop at 25 entries")
        tags.removeFirst()
        check(ProfileTags.adding("New entry", to: tags).count == 25, "removing a tag makes room for another")
        let corruptDirectory = directory.appendingPathComponent("corrupt")
        try FileManager.default.createDirectory(at: corruptDirectory, withIntermediateDirectories: true)
        let corruptFile = corruptDirectory.appendingPathComponent("events.json")
        let corruptData = Data("invalid existing file".utf8)
        try corruptData.write(to: corruptFile)
        let corruptStore = EventStore(directory: corruptDirectory)
        check(!corruptStore.save(event), "unreadable event storage rejects overwrites")
        let afterFailedSave = try Data(contentsOf: corruptFile)
        check(afterFailedSave == corruptData, "unreadable original data is retained")
        let parser = LocalPlanAssistant()
        let parsed = parser.extract("Maya has soccer practice tomorrow at 6 pm for an hour and a half.", profiles: [profile], now: Date())
        check(parsed.draft.profileID == profile.id && parsed.draft.durationMinutes == 90 && parsed.draft.activityType == .sports, "assistant extracts profile, activity, duration")
        check(Calendar.current.component(.hour, from: parsed.draft.startTime) == 18, "assistant extracts explicit evening time")
        let ambiguous = parser.extract("Maya has soccer tomorrow at 6 for 60 minutes", profiles: [profile], now: Date())
        check(ambiguous.missing.contains { $0.contains("AM or PM") }, "ambiguous clock time requires review")
        let morning = parser.extract("Run tomorrow at 8:30 am for 45 minutes", profiles: [], now: Date())
        check(Calendar.current.component(.hour, from: morning.draft.startTime) == 8 && Calendar.current.component(.minute, from: morning.draft.startTime) == 30 && morning.draft.durationMinutes == 45, "assistant supports non-demo times and durations")
        let provider = CountingProvider(series: hourly)
        let repository = ForecastRepository(provider: provider)
        async let first = repository.fetchConditions(latitude: 40, longitude: -73, range: hour...hour.addingTimeInterval(3600))
        async let second = repository.fetchConditions(latitude: 40, longitude: -73, range: hour...hour.addingTimeInterval(3600))
        _ = try await (first, second)
        _ = try await repository.fetchConditions(latitude: 40, longitude: -73, range: hour...hour.addingTimeInterval(3600))
        let count = await provider.count
        check(count == 1, "simultaneous requests coalesce and minute checks reuse cached forecast")
        // Absolute AQI grading is independent of concentration and exposure.
        for (value, category) in [(0, AQICategory.good), (50, .good), (51, .moderate), (100, .moderate), (101, .sensitive), (150, .sensitive), (151, .unhealthy), (200, .unhealthy), (201, .veryUnhealthy), (300, .veryUnhealthy), (301, .hazardous), (700, .hazardous)] {
            check(AQICategory.category(for: Double(value)) == category, "AQI boundary \(value)")
        }
        for boundary in [50.0, 100, 150, 200, 300] {
            check(AQICategory.category(for: boundary + 0.49) == AQICategory.category(for: boundary), "AQI rounds down consistently at \(boundary)")
            check(AQICategory.category(for: boundary + 0.5) == AQICategory.category(for: boundary + 1), "AQI rounds up consistently at \(boundary)")
        }
        for invalid in [Double?.none, -1, -.infinity, .infinity, .nan, Double.greatestFiniteMagnitude] {
            check(AQICategory.reading(invalid) == nil && AQICategory.category(for: invalid) == nil, "Invalid AQI is unavailable: \(String(describing: invalid))")
        }
        var air = series([
            .init(timestamp: hour, pm25: 50, usAQI: 180),
            .init(timestamp: hour.addingTimeInterval(3600), pm25: 40, usAQI: 160),
            .init(timestamp: hour.addingTimeInterval(7200), pm25: 40, usAQI: nil)
        ])
        air.fetchedAt = hour.addingTimeInterval(-3600)
        let multiHour = AQIWindow.assess(series: air, start: hour.addingTimeInterval(1800), end: hour.addingTimeInterval(5400))
        check(multiHour.peak == 180 && multiHour.coveredSeconds == 3600 && !multiHour.isPartial, "AQI peak spans partial overlapping hours")
        let missingAQI = AQIWindow.assess(series: air, start: hour.addingTimeInterval(5400), end: hour.addingTimeInterval(9000))
        check(missingAQI.peak == 160 && missingAQI.coveredSeconds == 1800 && missingAQI.isPartial, "AQI partial window does not imply full coverage")
        check(AQIWindow.assess(series: air, start: hour, end: hour.addingTimeInterval(3600)).peak == 180, "AQI excludes hour at exact end boundary")
        var duplicateAir = air; duplicateAir.samples.append(air.samples[0])
        check(AQIWindow.assess(series: duplicateAir, start: hour, end: hour.addingTimeInterval(3600)).coveredSeconds == 3600, "AQI repeated hours do not inflate coverage")
        var unhealthyPlan = plan; unhealthyPlan.startTime = hour; unhealthyPlan.durationMinutes = 60; unhealthyPlan.constraints = .init(timeFlexibility: .oneHour)
        let unhealthyOptions = CounterfactualEngine.evaluate(plan: unhealthyPlan, series: air, now: hour.addingTimeInterval(-1))
        check(unhealthyOptions.alternatives.contains { abs(($0.reductionPercent(for: .pm25) ?? 0) - 20) < 0.001 && $0.assessment.aqi.category == .unhealthy }, "20 percent lower particle exposure can still have Unhealthy AQI")

        func savedEvent(start: Date, minutes: Int, samples: [EnvironmentalSample], owner: UUID? = nil, place: ActivityLocation? = nil) -> ActivityEvent {
            let place = place ?? location
            var environment = series(samples); environment.fetchedAt = start.addingTimeInterval(-3600)
            let activity = ActivityPlan(profileID: owner ?? profile.id, activityType: .exercise, activityName: "Weekly fixture", location: place, startTime: start.addingTimeInterval(-3600), durationMinutes: minutes)
            let snapshot = ExposureSnapshot(environmentalWindow: SavedEnvironmentalWindow(location: place, start: start, end: start.addingTimeInterval(Double(minutes) * 60), series: environment), analyzedAt: environment.fetchedAt, source: environment.source, sourceUpdatedAt: environment.fetchedAt, originalStart: activity.startTime, selectedStart: start, pm25Mean: nil, apparentTemperatureC: nil, reductionPercent: nil)
            return ActivityEvent(plan: activity, selectedStart: start, selectedRoute: nil, analysis: snapshot, createdAt: start)
        }
        let weeklyEvent = savedEvent(start: hour.addingTimeInterval(1800), minutes: 120, samples: [
            .init(timestamp: hour, pm25: 10, usAQI: 30),
            .init(timestamp: hour.addingTimeInterval(3600), pm25: 20, usAQI: 180),
            .init(timestamp: hour.addingTimeInterval(7200), pm25: nil, usAQI: nil)
        ])
        let utc = TimeZone(secondsFromGMT: 0)!
        let weekNow = hour.addingTimeInterval(86400)
        func week(_ events: [ActivityEvent], now: Date? = nil) -> WeeklyExposureSummary {
            WeeklyExposureEngine.summarize(events: events, profileID: profile.id, now: now ?? weekNow, timeZone: utc)
        }
        let weighted = week([weeklyEvent])
        check(weighted.scheduledSeconds == 7200 && weighted.coveredSeconds == 5400 && weighted.missingSeconds == 1800, "weekly missing coverage excludes missing hours")
        check(weighted.categorySeconds[0] == 1800 && weighted.categorySeconds[3] == 3600, "weekly categories use time weights, not event peak")
        check(abs(weighted.pm25Mean! - 50.0 / 3) < 0.001 && weighted.pm25Integral == 25 && weighted.pm25Seconds == 5400, "weekly PM2.5 mean and integral use covered time")
        check(weighted.days.reduce(0) { $0 + $1.coveredSeconds } == weighted.coveredSeconds, "seven-day contributions reconcile")
        let clippedNow = week([weeklyEvent], now: hour.addingTimeInterval(4500))
        check(clippedNow.scheduledSeconds == 2700 && clippedNow.categorySeconds[3] == 900, "weekly ongoing event counts only elapsed portion at selected time")
        check(week([weeklyEvent], now: hour).scheduledSeconds == 0, "weekly future plans contribute nothing")
        var copy = weeklyEvent; copy.id = UUID()
        let deduped = week([weeklyEvent, copy])
        check(deduped.scheduledSeconds == 7200 && deduped.coveredSeconds == 5400 && deduped.pm25Integral == 25, "same-location overlapping events count once")
        check(deduped.contributions.reduce(0) { $0 + $1.aqiSeconds } == deduped.coveredSeconds, "contributing events do not double-count overlap")
        var otherPlace = location; otherPlace.longitude += 0.001
        let conflict = savedEvent(start: hour.addingTimeInterval(3600), minutes: 30, samples: air.samples, place: otherPlace)
        let conflicted = week([weeklyEvent, conflict])
        check(conflicted.conflictSeconds == 1800 && conflicted.coveredSeconds == 3600 && conflicted.pm25Seconds == 3600, "different locations exclude only conflicted time from both metrics")
        var otherProfile = weeklyEvent; otherProfile.plan.profileID = another.id
        check(week([otherProfile]).scheduledSeconds == 0 && week([weeklyEvent, otherProfile]).scheduledSeconds == 7200, "weekly profile isolation")
        check(WeeklyExposureEngine.summarize(events: [weeklyEvent], profileID: nil, now: weekNow, timeZone: utc).scheduledSeconds == 0, "no selected profile has no summary data")
        var legacy = weeklyEvent; legacy.analysis?.environmentalWindow = nil
        let legacyData = try JSONEncoder.appEncoder.encode(legacy)
        check(!String(decoding: legacyData, as: UTF8.self).contains("environmentalWindow"), "legacy snapshot omits new optional field")
        let decodedLegacy = try JSONDecoder.appDecoder.decode(ActivityEvent.self, from: legacyData)
        check(decodedLegacy.analysis?.environmentalWindow == nil && decodedLegacy.savedAQI.peak == nil && week([decodedLegacy]).coveredSeconds == 0, "older saved events decode with honest missing coverage")
        let savedRoundTrip = try JSONDecoder.appDecoder.decode(ActivityEvent.self, from: JSONEncoder.appEncoder.encode(weeklyEvent))
        check(savedRoundTrip == weeklyEvent && savedRoundTrip.analysis?.environmentalWindow?.series.source == "Synthetic regression fixture", "saved hourly data and provenance round trip")
        var lateForecast = weeklyEvent
        lateForecast.analysis?.environmentalWindow?.series.fetchedAt = weekNow
        check(week([lateForecast]).coveredSeconds == 0, "today's forecast never replaces past conditions")
        var mismatched = weeklyEvent; mismatched.plan.location = otherPlace
        check(week([mismatched]).coveredSeconds == 0 && mismatched.savedAQI.peak == nil, "saved environmental data must match event location")
        let periodStart = weighted.start
        let boundaryEvent = savedEvent(start: periodStart.addingTimeInterval(-1800), minutes: 60, samples: [.init(timestamp: periodStart.addingTimeInterval(-1800), pm25: 10, usAQI: 50)])
        check(week([boundaryEvent]).scheduledSeconds == 1800 && week([boundaryEvent]).coveredSeconds == 1800, "weekly start boundary clips crossing events")
        let invalidDataEvent = savedEvent(start: hour, minutes: 60, samples: [.init(timestamp: hour, pm25: -3, usAQI: -2)])
        check(week([invalidDataEvent]).pm25Mean == nil && week([invalidDataEvent]).coveredSeconds == 0, "invalid weekly values are missing, not zero exposure")
        let separateCoverage = savedEvent(start: hour, minutes: 60, samples: [.init(timestamp: hour, pm25: nil, usAQI: 30)])
        check(week([separateCoverage]).coveredSeconds == 3600 && week([separateCoverage]).pm25Seconds == 0, "AQI and particle coverage stay independent")
        let ny = TimeZone(identifier: "America/New_York")!
        let dstNow = ISO8601DateFormatter().date(from: "2026-03-09T04:00:00Z")!
        let dstWeek = WeeklyExposureEngine.summarize(events: [], profileID: profile.id, now: dstNow, timeZone: ny)
        check(dstWeek.days.count == 7 && dstWeek.days[6].start.timeIntervalSince(dstWeek.days[5].start) == 23 * 3600, "reporting calendar respects DST and seven local days")
        print("\(passed) regression checks passed")
    }
}
