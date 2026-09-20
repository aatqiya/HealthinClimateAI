import SwiftUI

extension AQICategory {
    var color: Color { SeverityLevel(rawValue: rawValue)!.color }
}

struct AQIBadge: View {
    let category: AQICategory
    var body: some View {
        Label {
            Text(category.label).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: category.rawValue >= 2 ? "exclamationmark.circle.fill" : "circle.fill")
                .foregroundStyle(category.color)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(category.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Air quality: \(category.label)")
    }
}

struct AQIReadingView: View {
    let window: AQIWindow
    var label = "Peak forecast AQI"
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(window.peak.map(String.init) ?? "—").font(.system(.title, design: .rounded, weight: .semibold)).monospacedDigit()
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            if let category = window.category { AQIBadge(category: category) }
            if window.peak == nil {
                Text("AQI unavailable · no covered hours").font(.caption).foregroundStyle(.secondary)
            } else if window.isPartial {
                Text("Partial data · \(hours(window.coveredSeconds)) of \(hours(window.totalSeconds)) hours. Peak applies only to covered time.").font(.caption).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .combine)
    }
    private func hours(_ seconds: Double) -> String { String(format: "%.1f", seconds / 3600) }
}

struct AQIScale: View {
    var category: AQICategory?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 3) {
                ForEach(AQICategory.allCases) { item in
                    VStack(spacing: 3) {
                        Image(systemName: "arrowtriangle.down.fill").font(.caption2)
                            .opacity(category == item ? 1 : 0)
                        Capsule().fill(item.color).frame(height: 6)
                    }.frame(maxWidth: .infinity)
                }
            }.accessibilityElement(children: .ignore)
                .accessibilityLabel("US AQI scale. \(category.map { "Selected range: \($0.label), \($0.range)" } ?? "No reading selected")")
            DisclosureGroup("Understanding US AQI") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(AQICategory.allCases) { item in
                        HStack(alignment: .top) {
                            Circle().fill(item.color).frame(width: 8, height: 8).padding(.top, 4)
                            Text(item.label).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            Text(item.range).monospacedDigit()
                        }.font(.caption)
                    }
                    Text("Peak forecast AQI is the highest provider-reported US AQI in an hour overlapping your activity. Values are rounded to the nearest whole number before grading. Partial data describes only covered time.")
                    Text("AQI describes outdoor ambient air. It is separate from the time-weighted PM2.5 exposure comparison. A lower-exposure option can still have unhealthy air quality.")
                    Link("US EPA · AirNow AQI guide", destination: URL(string: "https://www.airnow.gov/aqi/aqi-basics/")!)
                }.font(.footnote).padding(.top, 12)
            }.font(.subheadline)
        }
    }
}

/// Home uses the same full category badge as planning and saved-event details.
struct CurrentAQICard: View {
    let value: Double?
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Air quality", systemImage: "aqi.medium").font(.subheadline.weight(.medium))
            Text(AQICategory.reading(value).map { "\($0) US AQI" } ?? "Unavailable")
                .font(.system(.title2, design: .rounded, weight: .semibold))
            if let category = AQICategory.category(for: value) { AQIBadge(category: category) }
            Text("Hourly forecast").font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, minHeight: 128, alignment: .leading).padding(16)
            .background(ResilioTheme.surface, in: RoundedRectangle(cornerRadius: ResilioTheme.cardRadius))
            .accessibilityElement(children: .combine)
    }
}
