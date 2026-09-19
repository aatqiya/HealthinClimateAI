import SwiftUI

struct ProfilesView: View {
    @Environment(AppState.self) private var app
    @State private var editing: UserProfile?
    @State private var creating = false
    @State private var switching = false
    var body: some View {
        NavigationStack {
            List {
                if let profile = app.profiles.selectedProfile {
                    Section("Planning for") {
                        ProfileCard(profile: profile, selected: true)
                        Button("Switch profile", systemImage: "person.2") { switching = true }
                        Button("Edit profile", systemImage: "pencil") { editing = profile }
                    }
                    Section("Profile details") {
                        LabeledContent("Relationship", value: profile.relationship.label)
                        LabeledContent("Age", value: profile.age.map(String.init) ?? "Not provided")
                        LabeledContent("Home ZIP", value: profile.homeZipCode ?? "Not provided")
                        LabeledContent("Medical conditions", value: "\(profile.medicalConditions.count) added")
                        LabeledContent("Mental or cognitive conditions", value: "\(profile.mentalConditions.count) added")
                        LabeledContent("Medications", value: "\(profile.medications.count) added")
                    }
                } else {
                    ContentUnavailableView("Who are you planning for?", systemImage: "person.crop.circle.badge.plus", description: Text("Create a profile to start planning for yourself or someone you care for."))
                }
                Section { Button("Add another profile", systemImage: "plus") { creating = true } }
                Section("Your preferences") {
                    NavigationLink { SettingsView() } label: { Label("Settings & connections", systemImage: "gearshape") }
                    NavigationLink { LegalView() } label: { Label("Privacy & optional data", systemImage: "hand.raised") }
                }
            }.navigationTitle("Profile")
                .sheet(isPresented: $switching) { ProfileSwitcher() }
                .sheet(item: $editing) { profile in
                    ProfileEditorView(profile: profile, onSave: app.profiles.update, onDelete: {
                        if app.events.deleteEvents(for: profile.id) { app.profiles.delete(profile) }
                    })
                }
                .sheet(isPresented: $creating) { ProfileEditorView(profile: .init(name: "", relationship: .myself), onSave: app.profiles.add, onDelete: nil) }
        }
    }
}

struct ProfileCard: View {
    let profile: UserProfile
    let selected: Bool
    var body: some View {
        HStack(spacing: 14) {
            Text(String(profile.name.prefix(1)).uppercased()).font(.title2.bold())
                .frame(width: 48, height: 48).background(ResilioTheme.sage.opacity(0.22), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name).font(.headline)
                Text([profile.age.map { "Age \($0)" }, profile.source == .synthetic ? "Demo profile" : profile.relationship.label].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(ResilioTheme.tint).accessibilityLabel("Active profile") }
        }.padding(.vertical, 8).contentShape(Rectangle())
    }
}

struct ProfileSwitcher: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var creating = false
    var body: some View {
        NavigationStack {
            List {
                ForEach(app.profiles.profiles) { profile in
                    Button { app.profiles.select(profile.id); dismiss() } label: { ProfileCard(profile: profile, selected: profile.id == app.profiles.selectedProfileID) }.buttonStyle(.plain)
                }
                Button("Add profile", systemImage: "plus") { creating = true }
            }.navigationTitle("Planning for").toolbar { Button("Done") { dismiss() } }
                .sheet(isPresented: $creating) { ProfileEditorView(profile: .init(name: "", relationship: .myself), onSave: app.profiles.add, onDelete: nil) }
        }
    }
}

struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State var profile: UserProfile
    let onSave: (UserProfile) -> Void
    let onDelete: (() -> Void)?
    @State private var ageText = ""
    @State private var confirmingDelete = false
    var validAge: Bool { ageText.isEmpty || Int(ageText).map { (0...120).contains($0) } == true }
    var validZIP: Bool { let zip = profile.homeZipCode ?? ""; return zip.isEmpty || zip.range(of: #"^\d{5}(-\d{4})?$"#, options: .regularExpression) != nil }
    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Name", text: $profile.name).textContentType(.nickname)
                    Picker("Relationship", selection: $profile.relationship) { ForEach(ProfileRelationship.allCases) { Text($0.label).tag($0) } }
                    TextField("Age (optional)", text: $ageText).keyboardType(.numberPad)
                    if !validAge { Text("Enter an age from 0 to 120.").font(.caption).foregroundStyle(.red) }
                    TextField("Home ZIP code (optional)", text: Binding(get: { profile.homeZipCode ?? "" }, set: { profile.homeZipCode = $0.isEmpty ? nil : $0 })).keyboardType(.numbersAndPunctuation)
                    if !validZIP { Text("Enter a 5-digit US ZIP or ZIP+4.").font(.caption).foregroundStyle(.red) }
                    Text("Home ZIP helps show nearby conditions. Add exact activity addresses when scheduling.").font(.caption).foregroundStyle(.secondary)
                }
                TagInput(title: "Medical conditions", suggestions: HealthCondition.allCases.filter { $0.category != .mentalHealth }.map(\.label), values: $profile.medicalConditions)
                TagInput(title: "Mental or cognitive conditions", suggestions: HealthCategory.mentalHealth.conditions.map(\.label), values: $profile.mentalConditions)
                TagInput(title: "Medications", suggestions: ["Lisinopril", "Albuterol", "Metformin", "Atorvastatin"], values: $profile.medications)
                if onDelete != nil { Section { Button("Delete profile and its Resilio plans", role: .destructive) { confirmingDelete = true } } }
            }.navigationTitle(onDelete == nil ? "Create profile" : "Edit profile")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { profile.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines); profile.age = Int(ageText); onSave(profile); dismiss() }
                            .disabled(profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !validAge || !validZIP)
                    }
                }.onAppear { ageText = profile.age.map(String.init) ?? "" }
                .confirmationDialog("Delete \(profile.name) and their Resilio plans? External calendar copies will remain.", isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("Delete profile and plans", role: .destructive) { onDelete?(); dismiss() }
                }
        }
    }
}
