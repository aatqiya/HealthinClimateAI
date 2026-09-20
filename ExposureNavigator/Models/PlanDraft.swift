import Foundation

struct PlanDraft: Equatable {
    var selectedRoute: RouteOption?
    var editingEventID: UUID?
    var profileID: UUID?
    var activityName = ""
    var activityType: ActivityType = .other
    var addressQuery = ""
    var location: ActivityLocation?
    var startTime = Date().addingTimeInterval(3600)
    var durationMinutes = 60
    var flexibility: TimeFlexibility = .fixed
    var earliestStart: Date?
    var latestStart: Date?
}

extension PlanDraft {
    func activityPlan() -> ActivityPlan? {
        guard let profileID, let location else { return nil }
        let name = activityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        var earliest = earliestStart
        var latest = latestStart
        if flexibility == .flexible {
            earliest = earliest ?? startTime
            latest = latest ?? startTime.addingTimeInterval(3600)
            guard let earliest, let latest, earliest <= startTime, latest >= startTime, earliest <= latest, latest.timeIntervalSince(earliest) <= 86400 else { return nil }
        }
        return ActivityPlan(profileID: profileID, activityType: activityType, activityName: name, location: location, startTime: startTime, durationMinutes: max(15, min(480, durationMinutes)), constraints: .init(timeFlexibility: flexibility, earliestStart: flexibility == .flexible ? earliest : nil, latestStart: flexibility == .flexible ? latest : nil))
    }

    init(event: ActivityEvent) {
        editingEventID = event.id; profileID = event.profileID
        activityName = event.plan.activityName; activityType = event.plan.activityType
        addressQuery = event.plan.location.name; location = event.plan.location
        startTime = event.selectedStart; durationMinutes = event.plan.durationMinutes
        flexibility = event.plan.constraints.timeFlexibility
        earliestStart = event.plan.constraints.earliestStart; latestStart = event.plan.constraints.latestStart
        selectedRoute = event.selectedRoute
    }
}
