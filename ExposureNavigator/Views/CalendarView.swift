import SwiftUI
import EventKit

struct CalendarView: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var date = Date()
    @State private var selectedID: UUID?
    @State private var showingEvent = false
    var eventsForDay: [ActivityEvent] { app.events.events.filter { Calendar.current.isDate($0.selectedStart, inSameDayAs: date) }.sorted { $0.selectedStart < $1.selectedStart } }
    var externalForDay: [ExternalCalendarEvent] {
        let start = Calendar.current.startOfDay(for: date), end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: date))!
        return app.calendars.events.filter { $0.start < end && $0.end > start }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if typeSize.isAccessibilitySize {
                        DatePicker("Viewing date", selection: $date, displayedComponents: .date)
                    } else {
                        MonthOverview(selectedDate: $date, plannedDates: app.events.events.map(\.selectedStart) + app.calendars.events.map(\.start))
                    }
                }
                Section(date.formatted(date: .complete, time: .omitted)) {
                    if eventsForDay.isEmpty && externalForDay.isEmpty { Text("No plans for this date.").foregroundStyle(.secondary) }
                    ForEach(eventsForDay) { event in Button { open(event) } label: { EventRow(event: event, profile: app.profiles.profiles.first { $0.id == event.profileID }) }.buttonStyle(.plain) }
                    ForEach(externalForDay) { event in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(event.title).font(.headline)
                            Text(event.isAllDay ? "All day" : "\(event.start.formatted(date: .omitted, time: .shortened))–\(event.end.formatted(date: .omitted, time: .shortened))")
                            if let location = event.location, !location.isEmpty { Text(location).font(.caption) }
                            Text("Apple Calendar · \(event.calendarName)").font(.caption).foregroundStyle(.secondary)
                            Button("Plan around this event") {
                                var draft = PlanDraft(); draft.profileID = app.profiles.selectedProfileID; draft.activityName = event.title
                                draft.startTime = event.start; draft.durationMinutes = max(15, min(480, Int(event.end.timeIntervalSince(event.start) / 60)))
                                draft.addressQuery = event.location ?? ""; app.scheduleDraft = draft; app.selectedTab = .schedule
                            }
                            Text("Creates a separate Resilio plan. The original calendar event stays unchanged.").font(.caption2).foregroundStyle(.secondary)
                        }.padding(.vertical, 6)
                    }
                }
                Section("Upcoming Resilio plans") {
                    ForEach(app.events.upcoming.prefix(10)) { event in Button { open(event) } label: { EventRow(event: event, profile: app.profiles.profiles.first { $0.id == event.profileID }) }.buttonStyle(.plain) }
                }
                Section("Connected calendars") { CalendarConnectionsView(date: date) }
            }.resilioForm().navigationTitle("Calendar")
                .toolbar { Button("Today") { date = Date() } }
                .sheet(isPresented: $showingEvent) { if let selectedID { EventDetailView(eventID: selectedID) } }
                .onAppear { openRequested() }
                .onChange(of: app.selectedEventID) { _, _ in openRequested() }
                .task(id: date) { await app.calendars.refresh(date: date) }
                .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await app.calendars.refresh(date: date) } } }
                .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in Task { await app.calendars.refresh(date: date) } }
        }
    }
    func open(_ event: ActivityEvent) { date = event.selectedStart; selectedID = event.id; showingEvent = true }
    func openRequested() { if let id = app.selectedEventID, let event = app.events.events.first(where: { $0.id == id }) { open(event); app.selectedEventID = nil } }
}

struct MonthOverview: View {
    @Binding var selectedDate: Date
    let plannedDates: [Date]
    private let calendar = Calendar.current
    var monthStart: Date { calendar.dateInterval(of: .month, for: selectedDate)!.start }
    var cells: [Date?] {
        let offset = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: offset) + (calendar.range(of: .day, in: .month, for: monthStart) ?? 1..<2).map { calendar.date(byAdding: .day, value: $0 - 1, to: monthStart) }
    }
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button { changeMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("Previous month")
                Spacer(); Text(monthStart.formatted(.dateTime.month(.wide).year())).font(.headline); Spacer()
                Button { changeMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("Next month")
            }
            Grid(horizontalSpacing: 0, verticalSpacing: 4) {
                GridRow {
                    ForEach(0..<7) { index in
                        Text(calendar.veryShortStandaloneWeekdaySymbols[(index + calendar.firstWeekday - 1) % 7])
                            .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                }
                ForEach(0..<((cells.count + 6) / 7), id: \.self) { row in
                    GridRow {
                        ForEach(0..<7) { column in
                            let index = row * 7 + column
                            if index < cells.count, let date = cells[index] { dayButton(date) }
                            else { Color.clear.frame(maxWidth: .infinity).frame(height: 44) }
                        }
                    }
                }
            }

        }
    }
    func dayButton(_ date: Date) -> some View {
        let selected = calendar.isDate(date, inSameDayAs: selectedDate)
        let hasPlan = plannedDates.contains { calendar.isDate($0, inSameDayAs: date) }
        return Button { selectedDate = date } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: date))").font(.subheadline.weight(selected ? .bold : .regular))
                Circle().fill(hasPlan ? (selected ? .white : ResilioTheme.tint) : .clear).frame(width: 4, height: 4)
            }.frame(maxWidth: .infinity).frame(height: 44).foregroundStyle(selected ? .white : .primary)
                .background(selected ? ResilioTheme.forest : .clear, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityLabel(date.formatted(date: .complete, time: .omitted) + (hasPlan ? ", has events" : "")).accessibilityAddTraits(selected ? .isSelected : [])
    }
    func changeMonth(_ delta: Int) { selectedDate = calendar.date(byAdding: .month, value: delta, to: monthStart) ?? selectedDate }
}

struct EventDetailView: View {
    let eventID: UUID
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @AppStorage("temperatureUnit") private var unit = "fahrenheit"
    @State private var showResults = false
    @State private var exporting = false
    @State private var confirmingDelete = false
    @State private var fresh: ExposureAssessment?
    @State private var refreshedAt: Date?
    @State private var refreshError: String?
    var event: ActivityEvent? { app.events.events.first { $0.id == eventID } }
    var body: some View {
        NavigationStack {
            Group {
                if let event {
                    List {
                        Section {
                            Text(event.plan.activityName).font(.title2.bold())
                            LabeledContent("Profile", value: app.profiles.profiles.first { $0.id == event.profileID }?.name ?? "Deleted profile")
                            LabeledContent("Date", value: DisplayFormat.date(event.selectedStart, at: event.plan.location))
                            LabeledContent("Time", value: "\(DisplayFormat.time(event.selectedStart, at: event.plan.location))–\(DisplayFormat.time(event.endTime, at: event.plan.location))")
                            LabeledContent("Duration", value: "\(event.plan.durationMinutes) min")
                            Text(event.plan.location.formattedAddress.isEmpty ? event.plan.location.name : event.plan.location.formattedAddress)
                            Text(event.plan.location.timeZone.identifier).font(.caption).foregroundStyle(.secondary)
                            if let route = event.selectedRoute { Text("\(route.name) · \(route.durationMinutes) min travel"); Text("Route pollution differences are not estimated.").font(.caption) }
                        }
                        Section("Forecast for your plan") {
                            AQIReadingView(window: fresh?.aqi ?? event.savedAQI, label: fresh == nil ? "Saved peak forecast AQI" : "Peak forecast AQI")
                            AQIScale(category: (fresh?.aqi ?? event.savedAQI).category)
                            let pm = fresh == nil ? event.analysis?.pm25Mean : fresh?.metric(.pm25)?.meanConcentration
                            LabeledContent("Fine particle pollution", value: pm.map { "\(Int($0.rounded())) µg/m³" } ?? "Unavailable")
                            if let particle = fresh?.metric(.pm25) {
                                Text("PM2.5 estimate covers \(Int((particle.dataCoverage * 100).rounded()))% of activity time.").font(.caption).foregroundStyle(.secondary)
                            } else if fresh == nil, let window = event.analysis?.environmentalWindow,
                                      let particle = ExposureEngine.assess(series: window.series, start: event.selectedStart, durationMinutes: event.plan.durationMinutes).metric(.pm25) {
                                Text("Saved PM2.5 estimate covers \(Int((particle.dataCoverage * 100).rounded()))% of activity time.").font(.caption).foregroundStyle(.secondary)
                            } else if fresh == nil, pm != nil {
                                Text("Hourly coverage was not saved with this older PM2.5 estimate.").font(.caption).foregroundStyle(.secondary)
                            }
                            LabeledContent("Feels like", value: DisplayFormat.temperature(fresh == nil ? event.analysis?.apparentTemperatureC : fresh?.metric(.heat)?.meanConcentration, unit: unit))
                            if let refreshedAt { Text("Forecast retrieved \(refreshedAt.formatted())").font(.caption).foregroundStyle(.secondary) }
                            else if let analysis = event.analysis { Text("Saved estimate from \(analysis.analyzedAt.formatted())").font(.caption).foregroundStyle(.secondary) }
                            if let refreshError { Text(refreshError).font(.caption).foregroundStyle(.secondary) }
                        }
                        Section("Your saved choice") {
                            if let reduction = event.analysis?.reductionPercent { Text("When saved, this plan had \(Int(reduction.rounded()))% lower modeled particle exposure than the original time. Forecasts may have changed.") }
                            else { Text(event.analysis == nil ? "Saved without an exposure estimate." : "You kept your original plan.") }
                        }
                        if let profile = app.profiles.profiles.first(where: { $0.id == event.profileID }), let fresh { GuidanceSection(profile: profile, plan: event.plan, assessment: fresh) }
                        Section("What you can change") {
                            Button("Check alternatives again") { showResults = true }.disabled(event.endTime < Date())
                            Button("Edit plan") { app.scheduleDraft = PlanDraft(event: event); app.selectedTab = .schedule; dismiss() }
                            Button("Add a copy to Apple Calendar") { exporting = true }
                            Text("Apple opens an editor for you to review and save. Exported copies don't automatically sync with Resilio.").font(.caption).foregroundStyle(.secondary)
                        }
                        Section {
                            DisclosureGroup("Sources & details") {
                                Text(event.analysis?.source ?? OpenMeteoProvider.sourceName)
                                Text("Source update time is not supplied. Current forecast and saved comparison can come from different retrievals.")
                                Link("Open-Meteo & CAMS", destination: URL(string: "https://open-meteo.com/en/docs/air-quality-api")!)
                            }
                            Button("Delete event", role: .destructive) { confirmingDelete = true }
                        }
                    }
                } else { ContentUnavailableView("Event removed", systemImage: "calendar") }
            }.resilioForm().navigationTitle("Plan details").navigationBarTitleDisplayMode(.inline).toolbar { Button("Done") { dismiss() } }
                .task(id: event?.selectedStart) { await refresh() }
                .sheet(isPresented: $showResults) { if let event { NavigationStack { ResultsView(plan: event.plan, existingEventID: event.id, route: event.selectedRoute).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showResults = false } } } } } }
                .sheet(isPresented: $exporting) { if let event { AppleCalendarExportView(event: event, store: app.calendars.store) { exporting = false } } }
                .confirmationDialog("Delete this Resilio event? External calendar copies will remain.", isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("Delete event", role: .destructive) { if let event, app.events.delete(event) { dismiss() } }
                }
        }
    }
    func refresh() async {
        guard let event, event.endTime > Date() else { return }
        do {
            let series = try await ForecastRepository.shared.fetchConditions(latitude: event.plan.location.latitude, longitude: event.plan.location.longitude, range: event.selectedStart...event.endTime)
            let assessment = ExposureEngine.assess(series: series, start: event.selectedStart, durationMinutes: event.plan.durationMinutes)
            guard !assessment.metrics.isEmpty || assessment.aqi.peak != nil else { refreshError = "A current forecast is not yet available for this date. Showing any saved estimate."; return }
            fresh = assessment; refreshedAt = series.fetchedAt; refreshError = nil

        } catch { refreshError = "Couldn't refresh conditions. Any saved estimate is still shown." }
    }
}
