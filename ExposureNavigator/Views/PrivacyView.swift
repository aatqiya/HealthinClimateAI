import SwiftUI

struct PrivacyNote: View {
    var healthFields = false
    @State private var showingPrivacy = false
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.shield").foregroundStyle(ResilioTheme.tint).padding(.top, 2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(healthFields
                     ? "Health details are optional and help personalize guidance on this device. They are not sent to air-quality providers."
                     : "Your health details stay on your device. Air-quality requests share location coordinates, not your name or health profile.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("How your data is used") { showingPrivacy = true }
                    .font(.caption.weight(.semibold)).frame(minHeight: 44, alignment: .leading)
            }
        }.sheet(isPresented: $showingPrivacy) { PrivacyView() }
    }
}

struct PrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List { PrivacySections() }.resilioForm()
                .navigationTitle("How your data is used").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct PrivacySections: View {
    var body: some View {
        Section("On your device") {
            Text("Resilio stores profiles, optional health details, saved plans, locations, and saved environmental estimates in local app files. Your preferences are saved locally too. Device backups may include this data, depending on your settings.")
            Text("Health details personalize guidance locally. The plan assistant also runs on your device. Weekly summaries use your saved plans and hourly environmental estimates without making additional network requests.")
        }
        Section("What leaves your device") {
            Text("Air-quality and weather requests send coordinates to Open-Meteo. They do not include your name, health profile, or calendar event titles.")
            Text("Address searches, including a home ZIP used to find nearby conditions, go to Apple Maps. Apple location services may also resolve your current coordinates to a place name.")
            Text("External services receive ordinary network information, such as your IP address. Opening a source or policy link connects to that website.")
            if GoogleRoutesService.isConfigured {
                Text("Route planning is configured. When you request routes, starting and destination place names, addresses, coordinates, timezones, and travel mode go to the configured route server for Google route planning. Health details are not included.")
            } else {
                Text("Google route planning is not configured in this build. If enabled, route requests send starting and destination place names, addresses, coordinates, timezones, and travel mode to the configured route server.")
            }
            Text("This version has no advertising or analytics SDKs. Hosted AI, account sign-in, Google Calendar, and Outlook are not enabled.")
        }
        Section("Calendar & Apple Health") {
            Text("When you connect Apple Calendar, Resilio reads event titles, times, locations, and calendar names on your device. Making a Resilio plan from an event saves a separate local plan.")
            Text("Exporting opens Apple's calendar editor with the activity title, selected times, location, and timezone. The copy is saved only when you tap Save. Your chosen calendar account may sync it to its service. Health details and exposure estimates are not added to the export.")
            Text("The Apple Health connection only requests permission. Resilio does not currently read or store Apple Health measurements.")
        }
        Section("You stay in control") {
            Text("Remove health details in Edit Profile. Delete plans from Calendar, or delete a profile and its Resilio plans together. Exported calendar copies remain separate and can be removed in your calendar app.")
            Text("Disconnect Apple Calendar in Settings to stop displaying its events. Manage location, Calendar, and Health permissions in iOS Settings. You can enter locations yourself without enabling device location access.")
            Link("Apple privacy policy", destination: URL(string: "https://www.apple.com/legal/privacy/")!)
            Link("Open-Meteo privacy policy", destination: URL(string: "https://open-meteo.com/en/terms")!)
        }
    }
}
