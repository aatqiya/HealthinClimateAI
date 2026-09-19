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
        print("\(passed) regression checks passed")
    }
}
