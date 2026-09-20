import SwiftUI

enum ResilioTheme {
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
            .foregroundStyle(.white)
            .background(ResilioTheme.forest.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 18))
    }
}

extension View {
    func resilioCard() -> some View {
        padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(ResilioTheme.surface, in: RoundedRectangle(cornerRadius: 22))
    }
}

/// A shared bad-to-good scale so every reading that has an official category
/// (US AQI, EPA PM2.5 breakpoints, NWS heat index) renders with the same colors.
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
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(level.color)
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
        guard let aqi else { return nil }
        switch aqi { case ...50: return .good; case ...100: return .moderate; case ...150: return .elevated; case ...200: return .high; case ...300: return .veryHigh; default: return .extreme }
    }
    static func airQuality(_ aqi: Double?) -> String {
        guard let level = airQualityLevel(aqi) else { return "Unavailable" }
        switch level {
        case .good: return "Good"
        case .moderate: return "Moderate"
        case .elevated: return "Sensitive groups"
        case .high: return "Unhealthy"
        case .veryHigh: return "Very unhealthy"
        case .extreme: return "Hazardous"
        }
    }
    static func aqiBadge(_ aqi: Double?) -> (label: String, level: SeverityLevel)? {
        airQualityLevel(aqi).map { (airQuality(aqi), $0) }
    }
    /// EPA 24-hour PM2.5 NAAQS breakpoints in µg/m³ (airnow.gov/aqi/aqi-basics), for a raw
    /// forecast concentration where no AQI index has been computed (e.g. modeled exposure).
    static func pm25Level(_ microgramsPerCubicMeter: Double?) -> SeverityLevel? {
        guard let value = microgramsPerCubicMeter else { return nil }
        switch value { case ...9.0: return .good; case ...35.4: return .moderate; case ...55.4: return .elevated; case ...125.4: return .high; case ...225.4: return .veryHigh; default: return .extreme }
    }
    static func pm25Category(_ microgramsPerCubicMeter: Double?) -> String? {
        switch pm25Level(microgramsPerCubicMeter) {
        case .good: return "Good"
        case .moderate: return "Moderate"
        case .elevated: return "Sensitive groups"
        case .high: return "Unhealthy"
        case .veryHigh: return "Very unhealthy"
        case .extreme: return "Hazardous"
        case nil: return nil
        }
    }
    static func pm25Badge(_ microgramsPerCubicMeter: Double?) -> (label: String, level: SeverityLevel)? {
        guard let level = pm25Level(microgramsPerCubicMeter), let label = pm25Category(microgramsPerCubicMeter) else { return nil }
        return (label, level)
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
