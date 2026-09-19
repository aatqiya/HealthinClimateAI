import Foundation

enum PlanningPhase: Equatable {
    case collecting
    case analyzing
    case recommending
    case confirmed
}

enum PlanningSlot: String, Equatable {
    case profile, activity, date, time, place, duration, flexibility, placeChoice
}

enum ConversationRole: Equatable {
    case user, assistant, progress
}

struct ConversationMessage: Identifiable, Equatable {
    let id: UUID
    var role: ConversationRole
    var text: String

    init(id: UUID = UUID(), role: ConversationRole, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }

    static func user(_ text: String) -> Self { .init(role: .user, text: text) }
    static func assistant(_ text: String) -> Self { .init(role: .assistant, text: text) }
    static func progress(_ text: String) -> Self { .init(role: .progress, text: text) }
}

struct PlanningKnowledge: Equatable {
    var profile = false
    var activity = false
    var date = false
    var time = false
    var timeMeridiem = true
    var duration = false
    var place = false
    var flexibility = false
}

struct PlanningSession {
    var messages: [ConversationMessage] = []
    var draft = PlanDraft()
    var knowledge = PlanningKnowledge()
    var lastResult: CounterfactualResult?
    var lastSeries: EnvironmentalTimeSeries?
    var lastGuidance: [GuidanceItem] = []
    var lastPlan: ActivityPlan?
    var selectedAlternative: Alternative?
    var placeCandidates: [ActivityLocation] = []
    var awaiting: [PlanningSlot] = []
    var phase: PlanningPhase = .collecting
    var savedEvent: ActivityEvent?
    var environmentFetches = 0

    static func started() -> PlanningSession {
        var session = PlanningSession()
        session.messages = [
            .assistant("What's the plan? Tell me who, what, and when. I'll look up the place, check the forecast, and suggest safer start times when the time can move.\n\nI can't rank nearby routes — the forecast is for a place, not each trail.\n\nOn-device assistant · Voice uses LiveKit if you configure it; planning tools still run here.")
        ]
        return session
    }

    var canReviewInSchedule: Bool {
        draft.profileID != nil || !draft.activityName.isEmpty || draft.location != nil || knowledge.time
    }

    var canSave: Bool {
        (phase == .recommending || phase == .confirmed) && draft.activityPlan() != nil
    }

    var chosenStart: Date? {
        selectedAlternative?.assessment.start ?? lastResult?.original.start ?? lastPlan?.startTime
    }
}
