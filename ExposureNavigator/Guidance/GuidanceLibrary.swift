import Foundation

struct GuidanceItem: Identifiable {
    let id = UUID()
    var title: String
    var body: String
    var source: String
    var url: String
}

enum GuidanceLibrary {
    static func items(profile: UserProfile, plan: ActivityPlan, pm25Mean: Double?, apparentTemperatureC: Double?) -> [GuidanceItem] {
        var items: [GuidanceItem] = []
        if pm25Mean != nil {
            items.append(.init(title: "Air quality guidance", body: "This plan uses forecast fine-particle concentrations. AirNow explains practical ways to reduce exposure when particle levels rise. An hourly concentration is not itself an official daily air-quality category.", source: "U.S. EPA / AirNow", url: "https://www.airnow.gov/aqi/aqi-basics/"))
            let respiratory = profile.medicalConditions.contains { value in
                ["asthma", "copd", "lung", "bronchiectasis", "cystic fibrosis"].contains { value.localizedCaseInsensitiveContains($0) }
            }
            if respiratory {
                items.append(.init(title: "For respiratory conditions", body: "EPA and CDC guidance identifies people with asthma and other lung conditions among those who may be affected at lower particle levels. Follow an existing care plan and seek professional advice for personal medical questions.", source: "U.S. EPA / CDC", url: "https://www.cdc.gov/air-quality/about/index.html"))
            }
        }
        if let apparentTemperatureC, apparentTemperatureC >= 27 {
            items.append(.init(title: "Heat guidance", body: "CDC recommends fluids, breaks, shade or air conditioning, and moving strenuous activity to cooler times when possible.", source: "CDC", url: "https://www.cdc.gov/heat-health/"))
        }
        return items
    }

    static let limitations = [
        "Forecasts change. Re-check closer to the activity.",
        "Forecast grids may miss block-level differences.",
        "Modeled exposure is not a medical risk prediction."
    ]
}
