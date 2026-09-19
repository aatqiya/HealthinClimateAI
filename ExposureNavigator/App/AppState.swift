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
    let location = LocationManager()
    let calendars = CalendarService()
    var manualLocation: ActivityLocation? {
        didSet { if let data = try? JSONEncoder.appEncoder.encode(manualLocation) { UserDefaults.standard.set(data, forKey: "manualLocation") } }
    }

    init() {
        manualLocation = UserDefaults.standard.data(forKey: "manualLocation").flatMap { try? JSONDecoder.appDecoder.decode(ActivityLocation.self, from: $0) }
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
