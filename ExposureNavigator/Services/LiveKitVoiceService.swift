import Foundation
#if canImport(LiveKit)
import LiveKit
#endif

enum VoiceServiceError: LocalizedError {
    case setupRequired
    case sdkMissing
    case invalidResponse
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .setupRequired: return "Voice planning needs service setup. You can keep using text in this sheet."
        case .sdkMissing: return "The LiveKit SDK is not linked in this build. Add the LiveKit Swift package and try again."
        case .invalidResponse: return "The voice service returned a token this app couldn't read."
        case .connectionFailed(let message): return message
        }
    }
}

struct VoiceTokenRequest: Codable {
    var identity: String
    var room: String
}

struct VoiceTokenResponse: Codable {
    var url: String
    var token: String
    var room: String?
}

/// HTTPS token client. LiveKit API keys stay on the backend. See INTEGRATIONS.md.
enum LiveKitVoiceService {
    static var endpoint: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "RESILIO_VOICE_ENDPOINT") as? String,
              let url = URL(string: raw),
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1"].contains(url.host ?? "")) else { return nil }
        return url
    }

    static var isConfigured: Bool { endpoint != nil }

    static func token(identity: String, room: String) async throws -> VoiceTokenResponse {
        guard let endpoint else { throw VoiceServiceError.setupRequired }
        var http = URLRequest(url: endpoint)
        http.httpMethod = "POST"
        http.timeoutInterval = 20
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.httpBody = try JSONEncoder.appEncoder.encode(VoiceTokenRequest(identity: identity, room: room))
        let (data, response) = try await URLSession.shared.data(for: http)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw VoiceServiceError.invalidResponse }
        let token = try JSONDecoder.appDecoder.decode(VoiceTokenResponse.self, from: data)
        guard URL(string: token.url) != nil, !token.token.isEmpty else { throw VoiceServiceError.invalidResponse }
        return token
    }
}

@MainActor
@Observable
final class VoiceSessionController {
    var isActive = false
    var connecting = false
    var status = "Voice is off"
    var errorMessage: String?

    private let identity = "resilio-ios-\(UUID().uuidString.lowercased())"
    private let roomName = "resilio-\(UUID().uuidString.lowercased())"
#if canImport(LiveKit)
    private var room: Room?
#endif

    func start(
        makeBroker: @escaping () -> VoiceToolBroker,
        currentSession: @escaping () -> PlanningSession,
        apply: @escaping (PlanningSession) -> Void
    ) async {
        errorMessage = nil
        connecting = true
        status = "Connecting voice…"
        defer { connecting = false }
        do {
            try await connect(makeBroker: makeBroker, currentSession: currentSession, apply: apply)
            isActive = true
            status = "Listening"
        } catch {
            isActive = false
            status = "Voice is off"
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func stop() async {
#if canImport(LiveKit)
        await room?.disconnect()
        room = nil
#endif
        isActive = false
        connecting = false
        status = "Voice is off"
    }

    private func connect(
        makeBroker: @escaping () -> VoiceToolBroker,
        currentSession: @escaping () -> PlanningSession,
        apply: @escaping (PlanningSession) -> Void
    ) async throws {
        guard LiveKitVoiceService.isConfigured else { throw VoiceServiceError.setupRequired }
#if canImport(LiveKit)
        let credentials = try await LiveKitVoiceService.token(identity: identity, room: roomName)
        let room = Room()
        self.room = room
        for method in VoiceToolMethod.allCases {
            try await room.registerRpcMethod(method.rawValue) { data in
                try await self.perform(method: method.rawValue, payload: data.payload, makeBroker: makeBroker, currentSession: currentSession, apply: apply)
            }
        }
        try await room.connect(url: credentials.url, token: credentials.token)
        try await room.localParticipant.setMicrophone(enabled: true)
#else
        _ = makeBroker
        _ = currentSession
        _ = apply
        throw VoiceServiceError.sdkMissing
#endif
    }

    private func perform(
        method: String,
        payload: String,
        makeBroker: () -> VoiceToolBroker,
        currentSession: () -> PlanningSession,
        apply: (PlanningSession) -> Void
    ) async throws -> String {
        let broker = makeBroker()
        let updated = await broker.dispatch(method, payload: payload, session: currentSession())
        apply(updated)
        return try broker.response(for: updated)
    }
}
