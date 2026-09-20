import AVFoundation
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
        do {
            let (data, response) = try await URLSession.shared.data(for: http)
            guard let response = response as? HTTPURLResponse else { throw VoiceServiceError.invalidResponse }
            guard (200..<300).contains(response.statusCode) else {
                throw VoiceServiceError.connectionFailed("Token server returned HTTP \(response.statusCode). Is python3 token_server.py running?")
            }
            let token = try JSONDecoder.appDecoder.decode(VoiceTokenResponse.self, from: data)
            guard URL(string: token.url) != nil, !token.token.isEmpty else { throw VoiceServiceError.invalidResponse }
            return token
        } catch let error as VoiceServiceError {
            throw error
        } catch {
            throw VoiceServiceError.connectionFailed("Couldn't reach the voice token server at \(endpoint.absoluteString). Start VoiceAgent/start_token_server.sh.")
        }
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
        try LiveKitAudioSession.prepare()
        guard await LiveKitSDK.ensureDeviceAccess(for: [.audio]) else {
            throw VoiceServiceError.connectionFailed("Microphone permission was denied. Allow it, or in Simulator use I/O → Audio Input and pick your Mac microphone.")
        }
        let credentials = try await LiveKitVoiceService.token(identity: identity, room: roomName)
        let capture = LiveKitAudioSession.captureOptions
        let room = Room(roomOptions: RoomOptions(defaultAudioCaptureOptions: capture))
        self.room = room
        for method in VoiceToolMethod.allCases {
            try await room.registerRpcMethod(method.rawValue) { data in
                try await self.perform(method: method.rawValue, payload: data.payload, makeBroker: makeBroker, currentSession: currentSession, apply: apply)
            }
        }
        try await room.connect(url: credentials.url, token: credentials.token)
        do {
            try await room.localParticipant.setMicrophone(enabled: true, captureOptions: capture)
        } catch {
            throw VoiceServiceError.connectionFailed(LiveKitAudioSession.describe(error))
        }
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

#if canImport(LiveKit)
/// Simulator Voice Processing I/O commonly fails with -4010. Use software processing there.
private enum LiveKitAudioSession {
    static var captureOptions: AudioCaptureOptions {
        #if targetEnvironment(simulator)
        AudioCaptureOptions(
            echoCancellation: true,
            autoGainControl: true,
            noiseSuppression: true,
            echoCancellationMode: .software,
            autoGainControlMode: .software,
            noiseSuppressionMode: .software
        )
        #else
        AudioCaptureOptions()
        #endif
    }

    static func prepare() throws {
        AudioManager.shared.isSpeakerOutputPreferred = true
        #if targetEnvironment(simulator)
        AudioManager.shared.isVoiceProcessingBypassed = true
        try AudioManager.shared.setPlatformVoiceProcessingAllowed(false)
        #endif
    }

    static func describe(_ error: Error) -> String {
        let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        if text.contains("-4010") || text.localizedCaseInsensitiveContains("audio engine") {
            return "The simulator audio engine failed (-4010). In Simulator: I/O → Audio Input → your Mac microphone. Also allow Microphone for Simulator in macOS System Settings. A physical iPhone is more reliable."
        }
        return text
    }
}
#endif
