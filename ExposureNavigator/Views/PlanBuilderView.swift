import SwiftUI

struct PlanBuilderView: View {
    @Environment(AppState.self) private var app
    @State private var draft = PlanDraft()
    @State private var search = AddressSearchService()
    @State private var matches: [ActivityLocation] = []
    @State private var error: String?
    @State private var resolving = false
    @State private var builtPlan: ActivityPlan?
    @State private var origin: ActivityLocation?
    @State private var choosingOrigin = false
    @State private var mode: TransportMode = .walking
    @State private var routes: [RouteOption] = []
    @State private var routing = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Who") {
                    if app.profiles.profiles.isEmpty { Button("Create a profile to start") { app.selectedTab = .profile } }
                    Picker("Planning for", selection: $draft.profileID) {
                        Text("Choose a profile").tag(UUID?.none)
                        ForEach(app.profiles.profiles) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                Section("What") {
                    TextField("Event or activity name", text: $draft.activityName)
                    Picker("Activity", selection: $draft.activityType) { ForEach(ActivityType.allCases) { Text($0.label).tag($0) } }
                }
                Section("Where") {
                    TextField("Exact address or place", text: $draft.addressQuery).textContentType(.fullStreetAddress)
                        .onChange(of: draft.addressQuery) { _, value in
                            if draft.location?.name != value { draft.location = nil; draft.selectedRoute = nil; routes = []; matches = []; search.search(value) }
                        }
                    if draft.location == nil {
                        Button("Search for this place") { Task { await findPlaces() } }.disabled(resolving || draft.addressQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        ForEach(matches, id: \.self) { location in
                            Button { draft.location = location; draft.addressQuery = location.name; matches = []; search.suggestions = []; error = nil } label: {
                                VStack(alignment: .leading) { Text(location.name); Text(location.formattedAddress).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        ForEach(search.suggestions) { suggestion in
                            Button { Task { await select(suggestion) } } label: {
                                VStack(alignment: .leading) { Text(suggestion.title); Text(suggestion.subtitle).font(.caption).foregroundStyle(.secondary) }
                            }.disabled(resolving)
                        }
                    }
                    if let location = draft.location { Label(location.formattedAddress.isEmpty ? location.name : location.formattedAddress, systemImage: "mappin.circle.fill").font(.subheadline).foregroundStyle(.secondary) }
                    else { Text("Select a suggestion to confirm the exact place.").font(.caption).foregroundStyle(.secondary) }
                    if resolving { ProgressView("Finding address…") }
                }
                Section("When") {
                    DatePicker("Date", selection: $draft.startTime, in: Date()..., displayedComponents: .date)
                    DatePicker("Start time", selection: $draft.startTime, displayedComponents: .hourAndMinute)
                    Stepper("Duration: \(draft.durationMinutes) min", value: $draft.durationMinutes, in: 15...480, step: 15)
                    if let location = draft.location { Text("Times shown in \(location.timeZone.identifier).").font(.caption).foregroundStyle(.secondary) }
                }.environment(\.timeZone, draft.location?.timeZone ?? .current)
                Section("Can the start time change?") {
                    Picker("Flexibility", selection: $draft.flexibility) { ForEach(TimeFlexibility.allCases) { Text($0.label).tag($0) } }.pickerStyle(.inline)
                    if draft.flexibility == .flexible {
                        DatePicker("Earliest start", selection: Binding(get: { draft.earliestStart ?? draft.startTime }, set: { draft.earliestStart = $0 }))
                        DatePicker("Latest start", selection: Binding(get: { draft.latestStart ?? draft.startTime.addingTimeInterval(3600) }, set: { draft.latestStart = $0 }))
                        Text("Choose a window of up to 24 hours that includes your original start. Duration stays fixed.").font(.caption).foregroundStyle(.secondary)
                    }
                }.environment(\.timeZone, draft.location?.timeZone ?? .current)
                if draft.activityType.canUseRoutes || draft.activityType == .appointment { routeSection }
                if let validationMessage { Section { Text(validationMessage).font(.subheadline).foregroundStyle(.secondary) } }
                if let error { Section { Text(error).foregroundStyle(.secondary) } }
                Section {
                    Button("Explore options", action: build).buttonStyle(PrimaryButtonStyle()).disabled(!valid || resolving).opacity(valid && !resolving ? 1 : 0.45)
                    if draft.editingEventID != nil { Button("Cancel editing") { draft = PlanDraft(); draft.profileID = app.profiles.selectedProfileID } }
                } footer: { Text("Explore modeled exposure, then choose what fits. Resilio does not decide whether an activity is medically safe.") }
            }.resilioForm().navigationTitle(draft.editingEventID == nil ? "Schedule" : "Edit plan")
                .navigationDestination(item: $builtPlan) { plan in ResultsView(plan: plan, existingEventID: draft.editingEventID, route: draft.selectedRoute) }
                .onAppear(perform: loadDraft)
                .onChange(of: app.scheduleDraft) { _, incoming in if incoming != nil { loadDraft() } }
                .onChange(of: app.profiles.selectedProfileID) { _, id in if draft.editingEventID == nil { draft.profileID = id } }
                .onChange(of: draft.flexibility) { _, value in
                    if value == .flexible { draft.earliestStart = draft.startTime; draft.latestStart = draft.startTime.addingTimeInterval(3600) }
                }
                .onChange(of: draft.startTime) { old, new in
                    let delta = new.timeIntervalSince(old)
                    draft.earliestStart = draft.earliestStart?.addingTimeInterval(delta)
                    draft.latestStart = draft.latestStart?.addingTimeInterval(delta)
                }
                .sheet(isPresented: $choosingOrigin) { LocationPickerView { origin = $0; routes = []; draft.selectedRoute = nil } }
        }
    }
    var valid: Bool { draft.profileID != nil && app.profiles.profiles.contains { $0.id == draft.profileID } && !draft.activityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.location != nil && validationMessage == nil }
    var validationMessage: String? {
        if draft.startTime <= Date() { return "Choose a start time in the future." }
        if draft.flexibility == .flexible {
            let earliest = draft.earliestStart ?? draft.startTime, latest = draft.latestStart ?? draft.startTime.addingTimeInterval(3600)
            if earliest > draft.startTime || latest < draft.startTime || earliest > latest { return "Your time range must include the original start time." }
            if latest.timeIntervalSince(earliest) > 86400 { return "Choose a flexible window no longer than 24 hours." }
        }
        return nil
    }
    var routeSection: some View {
        Section("Getting there · optional") {
            if GoogleRoutesService.isConfigured {
                Button(origin?.name ?? "Choose starting address") { choosingOrigin = true }
                Picker("Travel by", selection: $mode) { ForEach(TransportMode.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }.onChange(of: mode) { _, _ in routes = []; draft.selectedRoute = nil }
                Button(routing ? "Finding routes…" : "Find routes") { Task { await findRoutes() } }.disabled(origin == nil || draft.location == nil || routing)
                ForEach(routes) { route in
                    Button { draft.selectedRoute = route } label: {
                        Label("\(route.name) · \(route.durationMinutes) min · \(String(format: "%.1f", route.distanceMeters / 1000)) km", systemImage: draft.selectedRoute?.id == route.id ? "checkmark.circle.fill" : "circle")
                    }
                }
                if draft.selectedRoute != nil { Button("Remove route") { draft.selectedRoute = nil } }
            } else { LabeledContent("Google route planning", value: "Setup required") }
            Text("Travel time is separate from activity duration. Available air-quality data cannot distinguish pollution between nearby routes.").font(.caption).foregroundStyle(.secondary)
        }
    }
    func loadDraft() {
        if let incoming = app.scheduleDraft {
            draft = incoming
            if draft.profileID == nil { draft.profileID = app.profiles.selectedProfileID }
            app.scheduleDraft = nil; builtPlan = nil
        }
        else if draft.editingEventID == nil { draft.profileID = app.profiles.selectedProfileID }
    }
    func select(_ suggestion: LocationSuggestion) async {
        let query = draft.addressQuery
        resolving = true; defer { resolving = false }
        do {
            let location = try await search.resolve(suggestion)
            guard query == draft.addressQuery else { return }
            draft.location = location; draft.addressQuery = location.name; search.suggestions = []; error = nil
        } catch { self.error = "Couldn't resolve that place. Try a more complete address." }
    }
    func findPlaces() async {
        let query = draft.addressQuery
        resolving = true; defer { resolving = false }
        do { let found = try await search.lookup(query); guard query == draft.addressQuery else { return }; matches = found; error = nil }
        catch { self.error = "Couldn't find that place. Add a city or street address and try again." }
    }
    func build() {
        guard valid, let profileID = draft.profileID, let location = draft.location else { return }
        builtPlan = ActivityPlan(profileID: profileID, activityType: draft.activityType, activityName: draft.activityName.trimmingCharacters(in: .whitespacesAndNewlines), location: location, startTime: draft.startTime, durationMinutes: draft.durationMinutes, constraints: .init(timeFlexibility: draft.flexibility, earliestStart: draft.flexibility == .flexible ? draft.earliestStart ?? draft.startTime : nil, latestStart: draft.flexibility == .flexible ? draft.latestStart ?? draft.startTime.addingTimeInterval(3600) : nil))
    }
    func findRoutes() async {
        guard let origin, let destination = draft.location else { return }
        routing = true; defer { routing = false }
        do { routes = try await GoogleRoutesService().routes(for: .init(origin: origin, destination: destination, mode: mode)); if routes.isEmpty { error = "No routes found for these places." } }
        catch { self.error = error.localizedDescription }
    }
}
