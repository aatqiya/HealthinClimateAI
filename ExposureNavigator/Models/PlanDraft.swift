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
