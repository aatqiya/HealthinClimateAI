import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var app
    @AppStorage("onboardingStep") private var step = 0
    @State private var terms = false
    @State private var privacy = false
    @State private var creatingProfile = false
    @State private var choosingLocation = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ResilioBrand(large: true).padding(.top, 24)
                    if step > 0 { Text("GETTING STARTED  ·  \(step) OF 4").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.secondary) }
                    VStack(alignment: .leading, spacing: 12) {
                        Text(title).font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text(bodyText).font(.title3).foregroundStyle(.secondary)
                    }
                    content
                    if step != 0 && step != 1 {
                        Button(step == 4 ? "Start planning" : "Continue", action: advance)
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled((step == 2 && (!terms || !privacy)) || (step == 4 && app.profiles.selectedProfile == nil))
                            .opacity((step == 2 && (!terms || !privacy)) || (step == 4 && app.profiles.selectedProfile == nil) ? 0.45 : 1)
                    }
                    if step > 0 { Button("Back") { step -= 1 }.frame(maxWidth: .infinity, minHeight: 44) }
                }.padding(24)
            }.background(ResilioTheme.background)
                .sheet(isPresented: $choosingLocation) { LocationPickerView { app.manualLocation = $0; advance() } }
                .sheet(isPresented: $creatingProfile) { ProfileEditorView(profile: .init(name: "", relationship: .myself), onSave: app.profiles.add, onDelete: nil) }
        }
    }
    @ViewBuilder var content: some View {
        switch step {
        case 0:
            VStack(spacing: 14) {
                Button("Continue on this device", action: advance).buttonStyle(PrimaryButtonStyle())
                Text("No account needed for this version. Profiles and plans are saved on this device. Account sign-in isn't available yet.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        case 1:
            VStack(spacing: 12) {
                Button("Use my location") { app.location.request(); advance() }.buttonStyle(PrimaryButtonStyle())
                Button("Enter a location") { choosingLocation = true }.frame(minHeight: 44)
                Button("I'll add a location later", action: advance).frame(minHeight: 44).foregroundStyle(.secondary)
            }
        case 2:
            VStack(spacing: 18) {
                NavigationLink("Read Terms of Service and Privacy Policy") { LegalView() }
                Toggle("I agree to the Terms of Service", isOn: $terms)
                Toggle("I agree to the Privacy Policy", isOn: $privacy)
            }.resilioCard()
        case 3:
            VStack(alignment: .leading, spacing: 16) {
                Label("Your health information is optional.", systemImage: "heart.text.square").font(.headline)
                Text("Resilio only considers information you voluntarily provide. You can use it without adding medical conditions, medications, mental health information, or other health details.")
                PrivacyNote(healthFields: true)
            }.resilioCard()
        default:
            VStack(alignment: .leading, spacing: 16) {
                ForEach(app.profiles.profiles) { profile in
                    Button { app.profiles.select(profile.id) } label: { ProfileCard(profile: profile, selected: profile.id == app.profiles.selectedProfileID) }.buttonStyle(.plain)
                }
                Button("Create a profile", systemImage: "person.badge.plus") { creatingProfile = true }.frame(minHeight: 44)
                Button("Try Maya, a demo profile") { app.profiles.addSampleProfiles() }.font(.subheadline).frame(minHeight: 44)
            }.resilioCard()
        }
    }
    var title: String { ["A little planning.\nA better day.", "Your day starts here.", "A clear agreement.", "You're in control.", "Who are you planning for?"][min(step, 4)] }
    var bodyText: String { ["Plan your day around the environment. Explore lower-exposure options that fit your real life.", "Use your location to see nearby air quality and heat. You can also enter a location yourself.", "Review the terms and privacy policy before continuing.", "Share only what feels right for you.", "Create a profile for yourself or someone you care for."][min(step, 4)] }
    func advance() {
        if step == 2 { UserDefaults.standard.set(Date(), forKey: "legalAcceptedAt"); UserDefaults.standard.set("1", forKey: "legalVersion") }
        if step < 4 { step += 1 } else { app.finishOnboarding() }
    }
}

struct LegalView: View {
    var body: some View {
        List {
            Section("Terms of Service · version 1") {
                Text("Resilio provides environmental planning information, not medical advice. It does not determine whether an activity is safe for you. You choose whether and how to change your plans.")
                Text("Forecasts and modeled estimates can be incomplete or change. Service availability depends on external providers. No environmental or health outcome is guaranteed.")
            }
            Section("Privacy Policy · version 1") {
                Text("Profiles, optional health details, and plans are stored on this device in protected app files. They are not sent to environmental services. Device backups may include app data according to your device settings.")
                Text("Address searches are sent to Apple Maps. Environmental requests send coordinates to Open-Meteo. If the place is in New York City, recent PM2.5 observations are also requested from NYC DOHMH / Queens College monitor files. These providers also receive normal network connection information. Location permission is optional. Health details are not sent.")
                Text("The plan assistant in this version runs locally. Optional voice uses ElevenLabs once you configure an agent; speech goes to that service, and planning tools still run on this device. Health details are not sent. No medical records or Apple Health data are accessed. If you connect Apple Calendar, events are read on this device. Export occurs only when you explicitly save in the Apple Calendar editor.")
                Text("You can remove health information in Edit Profile, delete plans in Calendar, and change location and calendar permissions in iOS Settings. Deleting a profile also deletes its Resilio plans after confirmation. External calendar copies are separate.")
                Link("Apple privacy policy", destination: URL(string: "https://www.apple.com/legal/privacy/")!)
                Link("Open-Meteo privacy policy", destination: URL(string: "https://open-meteo.com/en/terms")!)
            }
        }.navigationTitle("Terms & privacy").navigationBarTitleDisplayMode(.inline)
    }
}
