import Foundation

enum VoiceToolMethod: String, CaseIterable {
    case planningTurn = "planning_turn"
    case selectPlace = "select_place"
    case chooseAlternative = "choose_alternative"
    case savePlan = "save_plan"
    case sessionSnapshot = "session_snapshot"
}

struct VoiceToolPayload: Codable, Equatable {
    var message: String?
    var placeIndex: Int?
    var alternativeIndex: Int?
}

struct VoicePlaceCandidate: Codable, Equatable {
    var index: Int
    var name: String
    var address: String
}

struct VoiceTimeOption: Codable, Equatable {
    var index: Int
    var label: String
    var startTime: String
    var reductionPercent: Double?
}

struct VoiceGuidanceSummary: Codable, Equatable {
    var title: String
    var body: String
    var source: String
}

/// Redacted planning state for a hosted voice agent. Never includes health fields.
struct VoiceSessionSnapshot: Codable, Equatable {
    var phase: String
    var spokenReply: String
    var profileName: String?
    var activityName: String
    var placeName: String?
    var startTime: String?
    var durationMinutes: Int
    var flexibility: String
    var missing: [String]
    var placeCandidates: [VoicePlaceCandidate]
    var alternatives: [VoiceTimeOption]
    var originalPM25: Double?
    var originalHeatC: Double?
    var guidance: [VoiceGuidanceSummary]
    var canSave: Bool
    var saved: Bool
    var routeComparisonAvailable: Bool
}

enum VoicePlanningFormat {
    static func snapshot(session: PlanningSession, profiles: [UserProfile], now: Date = Date()) -> VoiceSessionSnapshot {
        let profileName = session.draft.profileID.flatMap { id in profiles.first { $0.id == id }?.name }
        let location = session.draft.location ?? session.lastPlan?.location
        let start = session.draft.startTime
        return VoiceSessionSnapshot(
            phase: phaseName(session.phase),
            spokenReply: spokenReply(session),
            profileName: profileName,
            activityName: session.draft.activityName,
            placeName: location?.name,
            startTime: session.knowledge.time ? iso(start) : nil,
            durationMinutes: session.draft.durationMinutes,
            flexibility: session.draft.flexibility.rawValue,
            missing: missing(session, profiles: profiles),
            placeCandidates: session.placeCandidates.enumerated().map {
                VoicePlaceCandidate(index: $0.offset + 1, name: $0.element.name, address: $0.element.formattedAddress)
            },
            alternatives: alternatives(session),
            originalPM25: session.lastResult?.original.metric(.pm25)?.meanConcentration,
            originalHeatC: session.lastResult?.original.metric(.heat)?.meanConcentration,
            guidance: session.lastGuidance.map { VoiceGuidanceSummary(title: $0.title, body: $0.body, source: $0.source) },
            canSave: session.canSave,
            saved: session.savedEvent != nil,
            routeComparisonAvailable: false
        )
    }

    static func encode(_ snapshot: VoiceSessionSnapshot) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return String(data: try encoder.encode(snapshot), encoding: .utf8) ?? "{}"
    }

    static func decodePayload(_ raw: String) -> VoiceToolPayload {
        let data = Data(raw.utf8)
        return (try? JSONDecoder().decode(VoiceToolPayload.self, from: data)) ?? VoiceToolPayload(message: raw.isEmpty ? nil : raw, placeIndex: nil, alternativeIndex: nil)
    }

    private static func phaseName(_ phase: PlanningPhase) -> String {
        switch phase {
        case .collecting: return "collecting"
        case .analyzing: return "analyzing"
        case .recommending: return "recommending"
        case .confirmed: return "confirmed"
        }
    }

    private static func spokenReply(_ session: PlanningSession) -> String {
        session.messages.last { $0.role == .assistant }?.text ?? "I'm ready to plan."
    }

    private static func missing(_ session: PlanningSession, profiles: [UserProfile]) -> [String] {
        var items: [String] = []
        if !session.knowledge.profile || session.draft.profileID == nil { items.append("profile") }
        if !session.knowledge.activity || session.draft.activityName.isEmpty { items.append("activity") }
        if !session.knowledge.date { items.append("date") }
        if !session.knowledge.time || !session.knowledge.timeMeridiem { items.append("time") }
        if !session.knowledge.place || session.draft.location == nil { items.append("place") }
        if !session.knowledge.duration { items.append("duration") }
        if !session.knowledge.flexibility { items.append("flexibility") }
        _ = profiles
        return items
    }

    private static func alternatives(_ session: PlanningSession) -> [VoiceTimeOption] {
        guard let result = session.lastResult, let location = session.lastPlan?.location ?? session.draft.location else { return [] }
        return result.alternatives.enumerated().map { index, alternative in
            let label: String
            if case .timeShift(let minutes) = alternative.change {
                label = minutes > 0 ? "Start \(minutes) minutes later" : "Start \(-minutes) minutes earlier"
            } else {
                label = "Alternative \(index + 1)"
            }
            return VoiceTimeOption(index: index + 1, label: "\(label) at \(PlanningFormat.time(alternative.assessment.start, at: location))", startTime: iso(alternative.assessment.start), reductionPercent: alternative.reductionPercent(for: .pm25))
        }
    }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
