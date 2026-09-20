import Foundation

/// Executes hosted voice agent tool calls on device (ElevenLabs client tools, or the legacy LiveKit RPC path). The hosted model only receives a redacted snapshot.
struct VoiceToolBroker {
    var agent: PlanningAgent
    var profiles: [UserProfile]
    var events: EventStore?
    var temperatureUnit: String
    var now: Date

    func dispatch(_ method: String, payload: String, session: PlanningSession) async -> PlanningSession {
        let body = VoicePlanningFormat.decodePayload(payload)
        switch VoiceToolMethod(rawValue: method) {
        case .planningTurn:
            let message = body.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !message.isEmpty else { return session }
            return await agent.handle(message, session: session, profiles: profiles, now: now, events: events, temperatureUnit: temperatureUnit)
        case .selectPlace:
            guard let index = body.placeIndex, session.placeCandidates.indices.contains(index - 1) else { return session }
            return await agent.selectPlace(session.placeCandidates[index - 1], session: session, profiles: profiles, now: now, temperatureUnit: temperatureUnit)
        case .chooseAlternative:
            let index = body.alternativeIndex ?? 0
            if index <= 0 {
                return agent.chooseAlternative(nil, session: session, temperatureUnit: temperatureUnit)
            }
            guard let alternatives = session.lastResult?.alternatives, alternatives.indices.contains(index - 1) else { return session }
            return agent.chooseAlternative(alternatives[index - 1], session: session, temperatureUnit: temperatureUnit)
        case .savePlan:
            return agent.save(session, events: events, profiles: profiles, now: now, unit: temperatureUnit)
        case .sessionSnapshot, .none:
            return session
        }
    }

    func response(for session: PlanningSession) throws -> String {
        try VoicePlanningFormat.encode(VoicePlanningFormat.snapshot(session: session, profiles: profiles, now: now))
    }
}
