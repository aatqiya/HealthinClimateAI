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
            Image("ResilioLogo").resizable().scaledToFit()
                .frame(width: large ? 72 : 36, height: large ? 72 : 36)
                .clipShape(RoundedRectangle(cornerRadius: large ? 20 : 10))
                .accessibilityHidden(true)
            Text("Resilio").font(large ? .largeTitle.bold() : .headline)
        }
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

enum DisplayFormat {
    static func temperature(_ celsius: Double?, unit: String) -> String {
        guard let celsius else { return "—" }
        return "\(Int((unit == "fahrenheit" ? celsius * 9 / 5 + 32 : celsius).rounded()))°\(unit == "fahrenheit" ? "F" : "C")"
    }
    static func airQuality(_ aqi: Double?) -> String {
        guard let aqi else { return "Unavailable" }
        switch aqi { case ...50: return "Good"; case ...100: return "Moderate"; case ...150: return "Sensitive groups"; case ...200: return "Unhealthy"; case ...300: return "Very unhealthy"; default: return "Hazardous" }
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
