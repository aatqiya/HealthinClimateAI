import SwiftUI

enum ResilioTheme {
    static let pageInset: CGFloat = 20
    static let cardRadius: CGFloat = 24
    static let controlRadius: CGFloat = 16
    static let sectionSpacing: CGFloat = 24
    static let cardInset: CGFloat = 20
    static let sage = Color(red: 0.59, green: 0.67, blue: 0.55)
    static let forest = Color(red: 0.24, green: 0.36, blue: 0.28)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let tint = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.67, green: 0.76, blue: 0.62, alpha: 1) : UIColor(red: 0.24, green: 0.36, blue: 0.28, alpha: 1)
    })
}

struct ResilioBrand: View {
    var large = false
    var body: some View {
        HStack(spacing: 12) {
            ResilioLogoMark(size: large ? 72 : 36)
            Text("Resilio").font(large ? .largeTitle.bold() : .headline)
        }
    }
}

/// The source artwork extends to the edges of its canvas, so it needs an inset
/// before clipping or the heart's curves get cropped flush against the corners.
struct ResilioLogoMark: View {
    var size: CGFloat
    var body: some View {
        Image("ResilioLogo").resizable().scaledToFit()
            .frame(width: size * 0.78, height: size * 0.78)
            .padding(size * 0.11)
            .background(ResilioTheme.surface, in: RoundedRectangle(cornerRadius: size * 0.3))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
            .foregroundStyle(.white)
            .background(ResilioTheme.forest.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45), in: RoundedRectangle(cornerRadius: ResilioTheme.controlRadius))
    }
}

extension View {
    func resilioForm() -> some View {
        scrollContentBackground(.hidden)
            .background(ResilioTheme.background)
            .listSectionSpacing(ResilioTheme.sectionSpacing)
            .environment(\.defaultMinListRowHeight, 48)
    }

    func resilioCard() -> some View {
        padding(ResilioTheme.cardInset).frame(maxWidth: .infinity, alignment: .leading)
            .background(ResilioTheme.surface, in: RoundedRectangle(cornerRadius: ResilioTheme.cardRadius))
    }
}

/// Shared category accents for provider-reported US AQI and modeled heat.
/// Raw particle concentrations are never given an AQI badge.
enum SeverityLevel: Int, Comparable {
    case good, moderate, elevated, high, veryHigh, extreme
    static func < (lhs: SeverityLevel, rhs: SeverityLevel) -> Bool { lhs.rawValue < rhs.rawValue }
    var color: Color {
        switch self {
        case .good: Color(red: 0.20, green: 0.55, blue: 0.30)
        case .moderate: Color(red: 0.80, green: 0.62, blue: 0.10)
        case .elevated: Color(red: 0.88, green: 0.45, blue: 0.12)
        case .high: Color(red: 0.80, green: 0.20, blue: 0.20)
        case .veryHigh: Color(red: 0.55, green: 0.20, blue: 0.55)
        case .extreme: Color(red: 0.42, green: 0.10, blue: 0.14)
        }
    }
}

struct SeverityBadge: View {
    let label: String
    let level: SeverityLevel
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(level.color).frame(width: 8, height: 8)
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(level.color.opacity(0.15), in: Capsule())
    }
}

enum DisplayFormat {
    static func temperature(_ celsius: Double?, unit: String) -> String {
        guard let celsius else { return "—" }
        return "\(Int((unit == "fahrenheit" ? celsius * 9 / 5 + 32 : celsius).rounded()))°\(unit == "fahrenheit" ? "F" : "C")"
    }
    /// U.S. AQI breakpoints (airnow.gov/aqi/aqi-basics), for an already-computed AQI index.
    static func airQualityLevel(_ aqi: Double?) -> SeverityLevel? {
        AQICategory.category(for: aqi).flatMap { SeverityLevel(rawValue: $0.rawValue) }
    }
    static func airQuality(_ aqi: Double?) -> String {
        AQICategory.category(for: aqi)?.label ?? "Unavailable"
    }
    static func aqiBadge(_ aqi: Double?) -> (label: String, level: SeverityLevel)? {
        airQualityLevel(aqi).map { (airQuality(aqi), $0) }
    }
    /// NWS heat index categories (weather.gov/safety/heat-index), applied to modeled apparent
    /// temperature in Celsius (26.7°C/32.2°C/39.4°C/51.7°C ≈ 80°F/90°F/103°F/125°F).
    static func heatLevel(_ apparentCelsius: Double?) -> SeverityLevel? {
        guard let value = apparentCelsius else { return nil }
        switch value { case ..<26.7: return .good; case ..<32.2: return .moderate; case ..<39.4: return .elevated; case ..<51.7: return .high; default: return .veryHigh }
    }
    static func heatCategory(_ apparentCelsius: Double?) -> String? {
        switch heatLevel(apparentCelsius) {
        case .good: return "Comfortable"
        case .moderate: return "Caution"
        case .elevated: return "Extreme caution"
        case .high, .veryHigh, .extreme: return "Danger"
        case nil: return nil
        }
    }
    static func heatBadge(_ apparentCelsius: Double?) -> (label: String, level: SeverityLevel)? {
        guard let level = heatLevel(apparentCelsius), let label = heatCategory(apparentCelsius) else { return nil }
        return (label, level)
    }
    static func date(_ date: Date, at location: ActivityLocation) -> String {
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeZone = location.timeZone
        return formatter.string(from: date)
    }
    static func time(_ date: Date, at location: ActivityLocation) -> String {
        let f = DateFormatter(); f.timeStyle = .short; f.timeZone = location.timeZone
        return f.string(from: date)
    }
}
