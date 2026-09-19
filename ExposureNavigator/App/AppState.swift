import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    enum Tab: Hashable { case home, schedule, calendar, profile }
    var selectedTab: Tab = .home
    var selectedEventID: UUID?
    var scheduleDraft: PlanDraft?
    var onboardingComplete: Bool
    let profiles = ProfileStore()
    let events = EventStore()
    let environment = EnvironmentStore()

    init() {
        onboardingComplete = UserDefaults.standard.bool(forKey: "onboardingComplete")
    }

    func finishOnboarding() {
        onboardingComplete = true
        UserDefaults.standard.set(true, forKey: "onboardingComplete")
    }

    func openEvent(_ event: ActivityEvent) {
        selectedEventID = event.id
        selectedTab = .calendar
    }
}

struct PlanDraft: Equatable {
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
