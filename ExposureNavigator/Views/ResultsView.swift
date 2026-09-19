import SwiftUI

struct ResultsView: View {
    let plan: ActivityPlan
    var existingEventID: UUID? = nil
    var route: RouteOption? = nil
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model = AnalysisViewModel()
    @State private var selected: Alternative?
    @State private var saved = false
    @AppStorage("temperatureUnit") private var unit = "fahrenheit"
    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading: ProgressView("Checking forecast conditions…")
            case .failed(let message):
                VStack(spacing: 20) {
                    ContentUnavailableView("Forecast unavailable", systemImage: "cloud", description: Text(message))
                    Button("Try again") { Task { await model.analyze(plan: plan) } }.buttonStyle(.bordered)
                    Button("Save original without analysis") { saveUnanalyzed() }.buttonStyle(.borderedProminent)
                    Text("No exposure estimate will be attached. You can check again from Calendar.").font(.caption).foregroundStyle(.secondary)
                }.padding()
            case .loaded(let result, let series):
                List {
                    Section("Your plan") {
                        Text(plan.activityName).font(.title2.bold())
                        Text(app.profiles.profiles.first { $0.id == plan.profileID }?.name ?? "Profile").foregroundStyle(ResilioTheme.tint)
                        Text(DisplayFormat.date(plan.startTime, at: plan.location) + " · " + timeRange(result.original))
                        Label(plan.location.name, systemImage: "mappin").foregroundStyle(.secondary)
                    }
                    Section("What we found") {
                        Text(summary(result))
                        LabeledContent("Fine particle pollution", value: result.original.metric(.pm25).map { "\(Int($0.meanConcentration.rounded())) µg/m³" } ?? "Unavailable")
                        LabeledContent("Feels like", value: DisplayFormat.temperature(result.original.metric(.heat)?.meanConcentration, unit: unit))
                    }
                    Section("Your options") {
                        OptionCard(title: "Keep original plan", assessment: result.original, location: plan.location, reduction: nil, selected: selected == nil) { selected = nil }
                        ForEach(result.alternatives) { alternative in
                            OptionCard(title: change(alternative), assessment: alternative.assessment, location: plan.location, reduction: alternative.reductionPercent(for: .pm25), selected: selected?.id == alternative.id) { selected = alternative }
                        }
                        if result.alternatives.isEmpty { Text("We didn't find a meaningfully lower-exposure option within the flexibility you provided.").foregroundStyle(.secondary) }
                    }
                    Section("Selected plan") {
                        let assessment = selected?.assessment ?? result.original
                        Label(timeRange(assessment), systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(ResilioTheme.tint)
                        Text("\(plan.durationMinutes) minutes · \(plan.location.timeZone.identifier)").font(.caption).foregroundStyle(.secondary)
                        if let route { Text("\(route.name) · \(route.durationMinutes) min travel") }
                        Button(existingEventID == nil ? "Save Event" : "Update Event") { save(result: result, series: series) }.buttonStyle(PrimaryButtonStyle()).disabled(saved)
                    }
                    if let profile = app.profiles.profiles.first(where: { $0.id == plan.profileID }) {
                        GuidanceSection(profile: profile, plan: plan, assessment: selected?.assessment ?? result.original)
                    }
                    Section {
                        DisclosureGroup("How was this estimated?") {
                            Text("Hourly forecast concentrations are weighted by the time your activity overlaps each hour. Duration stays fixed. This is modeled ambient exposure, not inhaled dose or a medical risk estimate.")
                            Text("Alternatives need complete particle data and at least 10% lower modeled exposure to appear. This display threshold is not a health threshold. Small forecast differences may be uncertain.")
                            if let particle = result.original.metric(.pm25) { LabeledContent("Original data coverage", value: "\(Int((particle.dataCoverage * 100).rounded()))%") }
                            Text("Heat and air quality can move in different directions. Check both when choosing a time.")
                            Text("Route comparisons do not estimate street-level pollution differences.")
                            Text("Source: \(series.source)")
                            Text("Retrieved: \(series.fetchedAt.formatted())")
                            Text("Source update time: not supplied by provider")
                            Link("Open-Meteo & CAMS sources", destination: URL(string: "https://open-meteo.com/en/docs/air-quality-api")!)
                        }.font(.subheadline)
                    }
                }
            }
        }.navigationTitle("Your options").navigationBarTitleDisplayMode(.inline)
            .task { await model.analyze(plan: plan) }
    }
    func timeRange(_ assessment: ExposureAssessment) -> String { "\(DisplayFormat.time(assessment.start, at: plan.location))–\(DisplayFormat.time(assessment.end, at: plan.location))" }
    func summary(_ result: CounterfactualResult) -> String {
        if result.bestMeaningful != nil { return "We found times with lower modeled particle exposure. Choose the option that fits your day." }
        if plan.constraints.timeFlexibility == .fixed { return "Your time is fixed, so we've checked conditions for your original plan." }
        if result.primaryPollutant == nil { return "There isn't enough complete particle data to compare times reliably. Available conditions are shown below." }
        return "No time we checked showed a large enough improvement to suggest a change."
    }
    func change(_ alternative: Alternative) -> String { switch alternative.change { case .timeShift(let minutes): return minutes > 0 ? "Start \(minutes) minutes later" : "Start \(-minutes) minutes earlier" } }
    func save(result: CounterfactualResult, series: EnvironmentalTimeSeries) {
        let assessment = selected?.assessment ?? result.original
        let snapshot = ExposureSnapshot(sourceRetrievedAt: series.fetchedAt, sourceMeasurementUpdatedAt: series.sourceUpdatedAt, analyzedAt: Date(), source: series.source, sourceUpdatedAt: series.fetchedAt, originalStart: plan.startTime, selectedStart: assessment.start, pm25Mean: assessment.metric(.pm25)?.meanConcentration, apparentTemperatureC: assessment.metric(.heat)?.meanConcentration, reductionPercent: selected?.reductionPercent(for: .pm25))
        persist(start: assessment.start, snapshot: snapshot)
    }
    func saveUnanalyzed() { persist(start: plan.startTime, snapshot: nil) }
    func persist(start: Date, snapshot: ExposureSnapshot?) {
        guard !saved, app.profiles.profiles.contains(where: { $0.id == plan.profileID }) else { return }
        let old = existingEventID.flatMap { id in app.events.events.first { $0.id == id } }
        let event = ActivityEvent(id: old?.id ?? UUID(), plan: plan, selectedStart: start, selectedRoute: route, analysis: snapshot, source: old?.source ?? .exposureNavigator, createdAt: old?.createdAt ?? Date())
        guard app.events.save(event) else { return }
        saved = true; app.scheduleDraft = PlanDraft(); app.openEvent(event); dismiss()
    }
}

struct OptionCard: View {
    let title: String
    let assessment: ExposureAssessment
    let location: ActivityLocation
    let reduction: Double?
    let selected: Bool
    let action: () -> Void
    @AppStorage("temperatureUnit") private var unit = "fahrenheit"
    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(ResilioTheme.tint).font(.title2)
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.headline)
                    Text("\(DisplayFormat.time(assessment.start, at: location))–\(DisplayFormat.time(assessment.end, at: location))")
                    if let reduction {
                        Text("\(Int(reduction.rounded()))% lower modeled fine particle exposure").font(.subheadline).foregroundStyle(ResilioTheme.tint)
                        Text("Forecast particle levels are lower over this time window.").font(.caption).foregroundStyle(.secondary)
                    }
                    if let heat = assessment.metric(.heat) { Text("Feels like \(DisplayFormat.temperature(heat.meanConcentration, unit: unit))").font(.caption).foregroundStyle(.secondary) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
struct GuidanceSection: View {
    let profile: UserProfile
    let plan: ActivityPlan
    let assessment: ExposureAssessment
    var body: some View {
        Section("Public-health information") {
            ForEach(GuidanceLibrary.items(profile: profile, plan: plan, pm25Mean: assessment.metric(.pm25)?.meanConcentration, apparentTemperatureC: assessment.metric(.heat)?.meanConcentration)) { item in
                DisclosureGroup(item.title) { Text(item.body); if let url = URL(string: item.url) { Link(item.source, destination: url) } }
            }
        }
    }
}
