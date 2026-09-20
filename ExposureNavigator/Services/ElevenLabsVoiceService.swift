import Combine
import ElevenLabs
import Foundation
import Observation

enum VoicePhase: Equatable {
    case disconnected
    case connecting
    case listening
    case thinking
    case speaking
    case error(String)
}

/// Voice transport for Plan with AI. ElevenLabs handles STT, turn-taking, and TTS;
/// every fact it speaks comes from `VoiceToolBroker` calling the on-device PlanningAgent —
/// the same engine the text composer uses. This service never computes exposure or plans itself.
@MainActor
@Observable
final class ElevenLabsVoiceService {
    private(set) var phase: VoicePhase = .disconnected
    private(set) var isMuted = false

    var isActive: Bool {
        switch phase {
        case .disconnected, .error: return false
        default: return true
        }
    }

    var connecting: Bool { phase == .connecting }

    var errorMessage: String? {
        if case .error(let message) = phase { return message }
        return nil
    }

    var status: String {
        switch phase {
        case .disconnected: return "Voice is off"
        case .connecting: return "Connecting…"
        case .listening: return "Listening"
        case .thinking: return "Thinking…"
        case .speaking: return "Speaking…"
        case .error: return "Voice is off"
        }
    }

    static var agentID: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "ELEVENLABS_AGENT_ID") as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.isEmpty || trimmed == "REPLACE_WITH_YOUR_ELEVENLABS_AGENT_ID") ? nil : trimmed
    }

    static var isConfigured: Bool { agentID != nil }

    @ObservationIgnored private var conversation: Conversation?
    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []
    @ObservationIgnored private var handledToolCallIDs: Set<String> = []

    func start(
        makeBroker: @escaping () -> VoiceToolBroker,
        currentSession: @escaping () -> PlanningSession,
        apply: @escaping (PlanningSession) -> Void
    ) async {
        guard let agentID = Self.agentID else {
            phase = .error("Voice AI needs setup. Add your ElevenLabs agent ID as ELEVENLABS_AGENT_ID in Xcode. You can keep using text in this sheet.")
            return
        }
        phase = .connecting
        handledToolCallIDs.removeAll()
        do {
            let conversation = try await ElevenLabs.startConversation(
                agentId: agentID,
                config: ConversationConfig(
                    onDisconnect: { [weak self] _ in
                        Task { @MainActor in self?.tearDown() }
                    },
                    onError: { [weak self] error in
                        Task { @MainActor in self?.phase = .error(error.errorDescription ?? "Voice AI had a problem. You can keep using text in this sheet.") }
                    },
                    onAgentStateChange: { [weak self] state in
                        Task { @MainActor in self?.applyAgentState(state) }
                    }
                )
            )
            self.conversation = conversation
            phase = .listening
            observe(conversation, makeBroker: makeBroker, currentSession: currentSession, apply: apply)
        } catch {
            phase = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func stop() async {
        cancellables.removeAll()
        let conversation = self.conversation
        self.conversation = nil
        await conversation?.endConversation()
        phase = .disconnected
    }

    func toggleMute() {
        guard let conversation else { return }
        Task {
            try? await conversation.toggleMute()
            isMuted = conversation.isMuted
        }
    }

    private func tearDown() {
        cancellables.removeAll()
        conversation = nil
        if isActive { phase = .disconnected }
    }

    private func applyAgentState(_ state: ElevenLabs.AgentState) {
        guard isActive else { return }
        switch state {
        case .listening: phase = .listening
        case .thinking: phase = .thinking
        case .speaking: phase = .speaking
        }
    }

    private func observe(
        _ conversation: Conversation,
        makeBroker: @escaping () -> VoiceToolBroker,
        currentSession: @escaping () -> PlanningSession,
        apply: @escaping (PlanningSession) -> Void
    ) {
        conversation.$pendingToolCalls
            .receive(on: DispatchQueue.main)
            .sink { [weak self] calls in
                guard let self else { return }
                for call in calls where !handledToolCallIDs.contains(call.toolCallId) {
                    handledToolCallIDs.insert(call.toolCallId)
                    Task {
                        await self.perform(call, makeBroker: makeBroker, currentSession: currentSession, apply: apply, conversation: conversation)
                    }
                }
            }
            .store(in: &cancellables)

        conversation.$isMuted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] muted in self?.isMuted = muted }
            .store(in: &cancellables)
    }

    private func perform(
        _ call: ClientToolCallEvent,
        makeBroker: () -> VoiceToolBroker,
        currentSession: () -> PlanningSession,
        apply: (PlanningSession) -> Void,
        conversation: Conversation
    ) async {
        let broker = makeBroker()
        let updated = await broker.dispatch(call.toolName, payload: Self.payload(for: call), session: currentSession())
        apply(updated)
        do {
            let result = try broker.response(for: updated)
            try await conversation.sendToolResult(for: call.toolCallId, result: result)
        } catch {
            try? await conversation.sendToolResult(for: call.toolCallId, result: "{}", isError: true, errorType: .externalClient)
        }
    }

    private static func payload(for call: ClientToolCallEvent) -> String {
        guard let parameters = try? call.getParameters(),
              let data = try? JSONSerialization.data(withJSONObject: parameters) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
