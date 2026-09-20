import SwiftUI

struct AIPlannerView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var parsed: ParsedPlan?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(ResilioTheme.tint)
                    Text("What's the plan?").font(.largeTitle.bold())
                    Text("Tell us who, what, and when. Then review the details before checking exposure.").foregroundStyle(.secondary)
                    Text("Your message is processed on this device. Review the draft for any missed details.").font(.caption).foregroundStyle(.secondary)
                    TextField("Maya has soccer practice tomorrow at 6 pm for an hour and a half.", text: $message, axis: .vertical)
                        .lineLimit(4...8).padding(16).background(ResilioTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                    Button("Create a draft") { parsed = LocalPlanAssistant().extract(message, profiles: app.profiles.profiles, now: Date()) }.buttonStyle(PrimaryButtonStyle()).disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let parsed {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Let's fill in the details.").font(.headline)
                            if !parsed.draft.activityName.isEmpty { Text(parsed.draft.activityName).font(.title3.bold()) }
                            if let profile = app.profiles.profiles.first(where: { $0.id == parsed.draft.profileID }) { Text("For \(profile.name)") }
                            ForEach(parsed.missing, id: \.self) { Text($0).font(.subheadline).foregroundStyle(.secondary) }
                        }.resilioCard()
                        Button("Review in Schedule") { app.scheduleDraft = parsed.draft; app.selectedTab = .schedule; dismiss() }.buttonStyle(PrimaryButtonStyle())
                    }
                }.padding(24)
            }.background(ResilioTheme.background).navigationTitle("Planning assistant").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Close") { dismiss() } }
        }
    }
}
