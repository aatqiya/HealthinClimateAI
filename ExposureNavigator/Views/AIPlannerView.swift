import SwiftUI

struct AIPlannerView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @AppStorage("temperatureUnit") private var unit = "fahrenheit"
    @State private var session = PlanningSession.started()
    @State private var message = ""
    @State private var busy = false
    @State private var bottomID = UUID()
    @State private var voice = VoiceSessionController()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(session.messages) { item in
                                messageBubble(item)
                            }
                            actionChips
                            Color.clear.frame(height: 1).id(bottomID)
                        }.padding(20)
                    }
                    .onChange(of: session.messages.count) { _, _ in
                        withAnimation { proxy.scrollTo(bottomID, anchor: .bottom) }
                    }
                }
                if let error = voice.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.bottom, 8)
                }
                composer
            }
            .background(ResilioTheme.background)
            .navigationTitle("Plan with AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Review in Schedule") { handoff() }
                        .disabled(!session.canReviewInSchedule)
                }
            }
            .onDisappear { Task { await voice.stop() } }
        }
    }

    @ViewBuilder private func messageBubble(_ item: ConversationMessage) -> some View {
        switch item.role {
        case .user:
            HStack {
                Spacer(minLength: 36)
                Text(item.text).padding(14).foregroundStyle(.white)
                    .background(ResilioTheme.forest, in: RoundedRectangle(cornerRadius: 18))
            }
        case .assistant:
            Text(item.text).padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ResilioTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        case .progress:
            HStack(spacing: 8) {
                if busy { ProgressView() }
                Text(item.text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var actionChips: some View {
        if !session.placeCandidates.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(session.placeCandidates, id: \.self) { location in
                    Button {
                        Task { await choosePlace(location) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(location.name).font(.headline)
                            if !location.formattedAddress.isEmpty {
                                Text(location.formattedAddress).font(.caption).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.bordered)
                }
            }
        }
        if session.phase == .recommending, let result = session.lastResult {
            VStack(alignment: .leading, spacing: 8) {
                Button("Keep original time") { session = agent.chooseAlternative(nil, session: session, temperatureUnit: unit) }
                    .buttonStyle(.bordered)
                ForEach(result.alternatives) { alternative in
                    Button(alternativeLabel(alternative)) {
                        session = agent.chooseAlternative(alternative, session: session, temperatureUnit: unit)
                    }.buttonStyle(.borderedProminent).tint(ResilioTheme.forest)
                }
                if session.canSave {
                    Button("Save plan") { persist() }.buttonStyle(PrimaryButtonStyle())
                }
            }
        }
        if session.phase == .confirmed, let event = session.savedEvent {
            Button("View in Calendar") { app.openEvent(event); dismiss() }.buttonStyle(PrimaryButtonStyle())
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Maya has a run tomorrow at 6 pm…", text: $message, axis: .vertical)
                .lineLimit(1...5)
                .padding(14)
                .background(ResilioTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            Button {
                Task { await toggleVoice() }
            } label: {
                Image(systemName: voice.isActive ? "mic.circle.fill" : "mic.circle")
                    .font(.system(size: 32))
                    .foregroundStyle(voice.isActive ? ResilioTheme.forest : .secondary)
            }
            .disabled(voice.connecting)
            .accessibilityLabel(voice.isActive ? "Stop voice" : "Start voice")
            Button {
                Task { await send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
                    .foregroundStyle(canSend ? ResilioTheme.forest : .secondary)
            }
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(ResilioTheme.background)
        .overlay(alignment: .top) {
            if voice.connecting || voice.isActive {
                Text(voice.status).font(.caption2).foregroundStyle(.secondary).padding(.top, -4)
            }
        }
    }

    private var canSend: Bool { !busy && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var agent: PlanningAgent {
        PlanningAgent(places: MapKitPlaceSearch(), environment: ForecastRepository.shared)
    }

    private func toggleVoice() async {
        if voice.isActive {
            await voice.stop()
            return
        }
        await voice.start(
            makeBroker: { VoiceToolBroker(agent: agent, profiles: app.profiles.profiles, events: app.events, temperatureUnit: unit, now: Date()) },
            currentSession: { session },
            apply: {
                session = $0
                if session.draft.profileID == nil { session.draft.profileID = app.profiles.selectedProfileID }
                if let event = $0.savedEvent { app.openEvent(event) }
            }
        )
    }

    private func send() async {
        let text = message
        message = ""
        busy = true
        defer { busy = false }
        session = await agent.handle(text, session: session, profiles: app.profiles.profiles, now: Date(), events: app.events, temperatureUnit: unit)
        if session.draft.profileID == nil { session.draft.profileID = app.profiles.selectedProfileID }
        if let event = session.savedEvent { app.openEvent(event) }
    }

    private func choosePlace(_ location: ActivityLocation) async {
        busy = true
        defer { busy = false }
        session = await agent.selectPlace(location, session: session, profiles: app.profiles.profiles, now: Date(), temperatureUnit: unit)
    }

    private func persist() {
        session = agent.save(session, events: app.events, profiles: app.profiles.profiles, now: Date(), unit: unit)
        if let event = session.savedEvent { app.openEvent(event) }
    }

    private func handoff() {
        var draft = session.draft
        if draft.profileID == nil { draft.profileID = app.profiles.selectedProfileID }
        app.scheduleDraft = draft
        app.selectedTab = .schedule
        dismiss()
    }

    private func alternativeLabel(_ alternative: Alternative) -> String {
        guard let location = session.draft.location ?? session.lastPlan?.location else {
            if case .timeShift(let minutes) = alternative.change {
                return minutes > 0 ? "Start \(minutes) min later" : "Start \(-minutes) min earlier"
            }
            return "Use this time"
        }
        let reduction = alternative.reductionPercent(for: .pm25).map { " · \(Int($0.rounded()))% lower particles" } ?? ""
        return "Use \(DisplayFormat.time(alternative.assessment.start, at: location))\(reduction)"
    }
}
