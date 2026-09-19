import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @AppStorage("temperatureUnit") private var unit = "fahrenheit"
    @State private var choosingLocation = false
    var body: some View {
        List {
            Section("Display") {
                Picker("Temperature", selection: $unit) { Text("Fahrenheit (°F)").tag("fahrenheit"); Text("Celsius (°C)").tag("celsius") }
            }
            Section("Home location") {
                LabeledContent("Location", value: app.manualLocation?.name ?? "Current location or profile ZIP")
                Button("Choose a city or address") { choosingLocation = true }
                Button("Use current location") { app.manualLocation = nil; app.location.request() }
                Button("Open iOS permissions") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            }
            Section("Calendar connections") { CalendarConnectionsView() }
            Section("Services") {
                LabeledContent("Address search", value: "Apple Maps")
                LabeledContent("Google Maps & routes", value: GoogleRoutesService.isConfigured ? "Configured · not verified" : "Setup required")
                LabeledContent("Plan assistant", value: "On-device parser")
                LabeledContent("Account sign-in", value: "Setup required")
                Text("Hosted AI, Google Calendar, and Outlook require service configuration. Your local profiles and plans work without an account.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Privacy") {
                NavigationLink("Terms & privacy") { LegalView() }
                Text("Health details are optional and stay on this device. Edit a profile to remove them. Environmental services receive location and time, never health details.").font(.subheadline)
                if let accepted = UserDefaults.standard.object(forKey: "legalAcceptedAt") as? Date { LabeledContent("Agreement recorded", value: accepted.formatted(date: .abbreviated, time: .omitted)) }
            }
            Section { ResilioBrand(); Text("Version 1.0 · Plan your day with a little more context.").font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $choosingLocation) { LocationPickerView { app.manualLocation = $0 } }
    }
}

struct CalendarConnectionsView: View {
    var date = Date()
    @Environment(AppState.self) private var app
    var body: some View {
        HStack {
            Label("Apple Calendar", systemImage: "calendar")
            Spacer()
            if app.calendars.loading { ProgressView() }
            else if app.calendars.connected { Button("Disconnect") { app.calendars.disconnect() } }
            else { Button("Connect") { Task { await app.calendars.connect(date: date) } } }
        }
        if app.calendars.connected { Text("Connected · Events are read from Apple Calendar. Export individual Resilio plans from their details.").font(.caption).foregroundStyle(.secondary) }
        LabeledContent("Google Calendar", value: "Setup required")
        LabeledContent("Microsoft Outlook", value: "Setup required")
        if let error = app.calendars.errorMessage { Text(error).font(.caption).foregroundStyle(.secondary) }
    }
}
