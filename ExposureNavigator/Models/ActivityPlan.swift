import Foundation

enum ActivityType: String, Codable, CaseIterable, Identifiable {
    case sports, exercise, commute, appointment, dogWalk, outdoorWork, leisure, other
    var id: String { rawValue }
    var label: String { switch self { case .sports:"Sports / practice"; case .exercise:"Exercise"; case .commute:"Commute"; case .appointment:"Appointment"; case .dogWalk:"Walk the dog"; case .outdoorWork:"Outdoor work"; case .leisure:"Time outside"; case .other:"Other" } }
    var isExertional: Bool { [.sports,.exercise,.outdoorWork].contains(self) }
    var canUseRoutes: Bool { [.commute,.dogWalk,.exercise].contains(self) }
}
struct ActivityLocation: Codable, Equatable, Hashable {
    var name: String
    var formattedAddress: String
    var latitude: Double
    var longitude: Double
    var timeZoneIdentifier: String?
    var timeZone: TimeZone { timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current }
}
enum TimeFlexibility: String, Codable, CaseIterable, Identifiable {
    case fixed, halfHour, oneHour, flexible
    var id: String { rawValue }
    var label: String { switch self { case .fixed:"No, the time is fixed"; case .halfHour:"Up to 30 minutes earlier or later"; case .oneHour:"Up to 1 hour earlier or later"; case .flexible:"Flexible" } }
    var minutes: Int { switch self { case .fixed:0; case .halfHour:30; case .oneHour:60; case .flexible:0 } }
}
struct PlanConstraints: Codable, Equatable, Hashable {
    var timeFlexibility: TimeFlexibility = .fixed
    var earliestStart: Date?
    var latestStart: Date?
    var timeFlexibilityMinutes: Int { timeFlexibility.minutes }
}
struct ActivityPlan: Identifiable, Codable, Equatable, Hashable {
    var id=UUID(); var profileID: UUID; var activityType: ActivityType; var activityName: String; var location: ActivityLocation; var startTime: Date; var durationMinutes: Int; var constraints=PlanConstraints()
    var endTime: Date { startTime.addingTimeInterval(TimeInterval(durationMinutes*60)) }
}
struct ExposureSnapshot: Codable, Equatable {
    var analyzedAt: Date; var source: String; var sourceUpdatedAt: Date; var originalStart: Date; var selectedStart: Date; var pm25Mean: Double?; var apparentTemperatureC: Double?; var reductionPercent: Double?
}
struct ActivityEvent: Identifiable, Codable, Equatable {
    var id=UUID(); var plan: ActivityPlan; var selectedStart: Date; var selectedRoute: RouteOption?; var analysis: ExposureSnapshot?; var source: CalendarSource = .exposureNavigator; var createdAt=Date()
    var profileID: UUID { plan.profileID }; var endTime: Date { selectedStart.addingTimeInterval(TimeInterval(plan.durationMinutes*60)) }
}
enum TransportMode: String, Codable, CaseIterable { case walking, cycling, driving }
struct RouteOption: Identifiable, Codable, Equatable { var id=UUID(); var name:String; var durationMinutes:Int; var distanceMeters:Double; var encodedPolyline:String?; var mode:TransportMode; var environmentalComparisonAvailable=false }
enum CalendarSource: String, Codable { case exposureNavigator="Exposure Navigator", apple="Apple Calendar", google="Google Calendar", outlook="Outlook" }
