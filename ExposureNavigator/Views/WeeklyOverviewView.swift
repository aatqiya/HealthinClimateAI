import SwiftUI

private struct WeeklyInput: Equatable {
    var events: [ActivityEvent]
    var profileID: UUID?
    var now: Date
    var timeZone: TimeZone
}

struct WeeklyOverviewView: View {
    let events: [ActivityEvent]
    let profileID: UUID?
    let now: Date
    var storageError: String?
    let schedule: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var summary: WeeklyExposureSummary?
    @State private var loadedProfileID: UUID?
    @State private var showingDetails = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your week in air quality").font(.title2.bold()).accessibilityAddTraits(.isHeader)
            if let storageError {
                Label("Weekly overview unavailable", systemImage: "exclamationmark.circle").font(.headline)
                Text(storageError).font(.subheadline).foregroundStyle(.secondary)
            } else if let summary, loadedProfileID == profileID {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(date(summary.start))–\(date(summary.end))").font(.subheadline.weight(.medium))
                    Text("Estimated from your calendar").font(.caption).foregroundStyle(.secondary)
                }
                if typeSize.isAccessibilitySize {
                    distribution(summary)
                    coverage(summary)
                } else {
                    HStack(spacing: 20) { distribution(summary); coverage(summary) }
                }
                if summary.coveredSeconds > 0 {
                    Text(summary.insight).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                    DisclosureGroup("Air-quality breakdown") {
                    ForEach(AQICategory.allCases.filter { summary.categorySeconds[$0.rawValue] > 0 }) { category in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(category.color).frame(width: 7, height: 7).accessibilityHidden(true)
                            Text(category.label)
                            Spacer(minLength: 4)
                            Text("\(hours(summary.categorySeconds[category.rawValue])) h").monospacedDigit()
                        }.font(.caption)
                    }
                    }.font(.caption.weight(.medium))
                } else {
                    Text(summary.scheduledSeconds > 0 ? "An incomplete picture" : "A fresh start to your week").font(.headline)
                    Text(summary.insight).font(.subheadline).foregroundStyle(.secondary)
                    Button("Schedule an activity", action: schedule).font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                }
                WeeklyTimeline(summary: summary)
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.pm25Mean.map { "Average PM2.5 · \(String(format: "%.1f", $0)) µg/m³" } ?? "Average PM2.5 · unavailable").font(.subheadline.weight(.medium))
                    Text("Based on \(hours(summary.pm25Seconds)) of \(hours(summary.scheduledSeconds)) scheduled hours").font(.caption).foregroundStyle(.secondary)
                }
                Button { showingDetails = true } label: {
                    HStack { Text("View week & calculation"); Spacer(); Image(systemName: "arrow.up.right") }
                        .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                }
                Text("Saved estimates of ambient conditions, not measured personal exposure.").font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView("Preparing your week…").frame(maxWidth: .infinity, minHeight: 180)
            }
        }.resilioCard()
            .task(id: WeeklyInput(events: events, profileID: profileID, now: now, timeZone: .current)) {
                let input = WeeklyInput(events: events, profileID: profileID, now: now, timeZone: .current)
                let computed = await Task.detached(priority: .userInitiated) {
                    WeeklyExposureEngine.summarize(events: input.events, profileID: input.profileID, now: input.now, timeZone: input.timeZone)
                }.value
                guard !Task.isCancelled else { return }
                summary = computed
                loadedProfileID = profileID
            }
            .sheet(isPresented: $showingDetails) { if let summary { WeeklyDetailView(summary: summary) } }
    }
    private func distribution(_ summary: WeeklyExposureSummary) -> some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.12), lineWidth: 14)
            ForEach(AQICategory.allCases) { category in
                let denominator = max(1, summary.scheduledSeconds)
                let start = summary.categorySeconds.prefix(category.rawValue).reduce(0, +) / denominator
                let end = start + summary.categorySeconds[category.rawValue] / denominator
                if end > start {
                    Circle().trim(from: start, to: end).stroke(category.color, style: StrokeStyle(lineWidth: 14, lineCap: .butt)).rotationEffect(.degrees(-90))
                }
            }
            if !typeSize.isAccessibilitySize {
            VStack(spacing: 3) {
                Text(hours(summary.coveredSeconds)).font(.system(.title, design: .rounded, weight: .semibold)).monospacedDigit()
                Text("hours covered").font(.caption2).foregroundStyle(.secondary)
            }
            }
        }.frame(width: 128, height: 128).padding(8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(hours(summary.coveredSeconds)) hours with AQI coverage. \(hours(summary.missingSeconds)) hours missing. Category breakdown below.")
    }
    private func coverage(_ summary: WeeklyExposureSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if typeSize.isAccessibilitySize { Text("\(hours(summary.coveredSeconds)) h with AQI coverage").font(.headline) }
            Text("\(hours(summary.scheduledSeconds)) h scheduled").font(.headline)
            Text(summary.missingSeconds > 0 ? "\(hours(summary.missingSeconds)) h without AQI data" : (summary.scheduledSeconds > 0 ? "All elapsed time covered" : "No elapsed activities yet")).font(.subheadline).foregroundStyle(.secondary)
            if summary.conflictSeconds > 0 {
                Label("\(hours(summary.conflictSeconds)) h with conflicting locations", systemImage: "exclamationmark.circle").font(.caption)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func date(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.timeZone = summary?.timeZone ?? .current
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter.string(from: date)
    }
}

private func hours(_ seconds: Double) -> String { String(format: "%.1f", seconds / 3600) }

struct WeeklyTimeline: View {
    let summary: WeeklyExposureSummary
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(summary.days) { day in
                    Text("\(weeklyDate(day.start, in: summary.timeZone)): \(hours(day.coveredSeconds)) h covered").font(.caption)
                }
            }
        } else {
        HStack(alignment: .top, spacing: 8) {
            ForEach(summary.days) { day in
                VStack(spacing: 6) {
                    GeometryReader { geometry in
                        HStack(spacing: 0) {
                            ForEach(AQICategory.allCases) { category in
                                Rectangle().fill(category.color)
                                    .frame(width: geometry.size.width * day.categorySeconds[category.rawValue] / max(1, day.scheduledSeconds))
                            }
                            Spacer(minLength: 0)
                        }.background(Color.secondary.opacity(0.12)).clipShape(Capsule())
                    }.frame(height: 6)
                    Text(weeklyDate(day.start, in: summary.timeZone, weekday: true)).font(.caption)
                    Text(day.scheduledSeconds == 0 ? "—" : "\(hours(day.coveredSeconds))").font(.caption2).monospacedDigit()
                }.frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(weeklyDate(day.start, in: summary.timeZone)): \(hours(day.coveredSeconds)) of \(hours(day.scheduledSeconds)) hours covered")
            }
        }.environment(\.timeZone, summary.timeZone)
        }
    }
}

struct WeeklyDetailView: View {
    let summary: WeeklyExposureSummary
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Estimated from your calendar") {
                    Text("\(weeklyDate(summary.start, in: summary.timeZone)) through \(weeklyDate(summary.end, in: summary.timeZone, time: true))")
                    Text("Reporting timezone: \(summary.timeZone.identifier)").font(.caption).foregroundStyle(.secondary)
                    Text("Includes this profile's saved Resilio plans. Apple Calendar events must first be made into a Resilio plan for this profile.")
                    Text("These are estimated outdoor ambient conditions during scheduled activities. They do not confirm attendance, measure personal exposure, or measure indoor air quality.")
                }
                Section("Coverage & estimates") {
                    LabeledContent("Elapsed scheduled time", value: "\(hours(summary.scheduledSeconds)) h")
                    LabeledContent("AQI coverage", value: "\(hours(summary.coveredSeconds)) h")
                    LabeledContent("Missing AQI coverage", value: "\(hours(summary.missingSeconds)) h")
                    LabeledContent("Conflicting locations", value: "\(hours(summary.conflictSeconds)) h")
                    LabeledContent("PM2.5 coverage", value: "\(hours(summary.pm25Seconds)) h")
                    LabeledContent("Average PM2.5", value: summary.pm25Mean.map { "\(String(format: "%.1f", $0)) µg/m³" } ?? "Unavailable")
                    LabeledContent("Cumulative modeled PM2.5", value: summary.pm25Seconds > 0 ? "\(String(format: "%.1f", summary.pm25Integral)) µg·h/m³" : "Unavailable")
                    Text("Missing time is not counted as zero exposure. AQI and PM2.5 can have different coverage.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Seven days") {
                    ForEach(summary.days) { day in
                        DisclosureGroup {
                            ForEach(AQICategory.allCases.filter { day.categorySeconds[$0.rawValue] > 0 }) { category in
                                LabeledContent(category.label, value: "\(hours(day.categorySeconds[category.rawValue])) h")
                            }
                            Text("\(hours(max(0, day.scheduledSeconds - day.coveredSeconds))) h without AQI coverage").font(.caption)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(weeklyDate(day.start, in: summary.timeZone))
                                Text("\(hours(day.coveredSeconds)) of \(hours(day.scheduledSeconds)) h covered").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("How we calculate it") {
                    Text("Each hourly AQI contributes only the time it overlaps an elapsed activity, clipped to this reporting period. The ring shows category hours as a share of elapsed scheduled time; gray represents missing coverage, not a health target.")
                    Text("Overlaps at the same coordinates count once. We use the most recently retrieved saved data available for each metric before that interval. Overlaps at different coordinates are excluded from both metrics because we cannot know which location you attended.")
                    Text("Average PM2.5 is weighted by covered time. Cumulative modeled PM2.5 is concentration multiplied by those hours, in µg·h/m³. Neither is an inhaled dose or a health score.")
                    Text("Saved forecasts remain estimates. We do not replace past conditions with today's forecast. Older plans without hourly records appear as missing coverage.")
                    AQIScale(category: nil)
                }
                Section("Contributing plans") {
                    if summary.contributions.isEmpty { Text("No elapsed plans in this reporting period.").foregroundStyle(.secondary) }
                    ForEach(summary.contributions) { contribution in
                        DisclosureGroup(contribution.event.plan.activityName) {
                            let event = contribution.event
                            Text(event.plan.location.name)
                            Text("\(weeklyDate(event.selectedStart, in: summary.timeZone, time: true))–\(weeklyDate(event.endTime, in: summary.timeZone, time: true))")
                            Text("Counted once: AQI \(hours(contribution.aqiSeconds)) h · PM2.5 \(hours(contribution.pm25Seconds)) h")
                            if let window = event.analysis?.environmentalWindow {
                                Text("\(window.series.kind.label) estimate · \(window.series.source)")
                                Text("Retrieved \(weeklyDate(window.series.fetchedAt, in: summary.timeZone, time: true))")
                                if let updated = window.series.sourceUpdatedAt { Text("Source updated \(weeklyDate(updated, in: summary.timeZone, time: true))") }
                                else { Text("Source update time not supplied.") }
                                Text(window.series.intervalSemantics)
                            } else { Text("No saved hourly data. A summary alone cannot establish hourly coverage.") }
                        }.font(.subheadline)
                    }
                }
            }.resilioForm().navigationTitle("Your week").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .environment(\.timeZone, summary.timeZone)
        }
    }
}

private func weeklyDate(_ date: Date, in timeZone: TimeZone, time: Bool = false, weekday: Bool = false) -> String {
    let formatter = DateFormatter(); formatter.timeZone = timeZone
    if weekday { formatter.setLocalizedDateFormatFromTemplate("EEEEE") }
    else { formatter.dateStyle = .medium; formatter.timeStyle = time ? .short : .none }
    return formatter.string(from: date)
}
