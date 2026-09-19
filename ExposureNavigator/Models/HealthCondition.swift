import Foundation

/// A user-entered condition. This layer is deliberately separate from the
/// guidance-matching layer: entering a condition here never implies that an
/// authoritative source names that condition for a given exposure.
enum HealthCondition: String, Codable, CaseIterable, Identifiable {
    // Respiratory
    case asthma
    case copd
    case interstitialLungDisease
    case bronchiectasis
    case cysticFibrosis

    // Cardiovascular
    case hypertension
    case hyperlipidemia
    case arrhythmia
    case heartFailure
    case previousStroke
    case peripheralVascularDisease
    case coronaryHeartDisease

    // Metabolic
    case diabetesMellitus

    // Mental health / evidence-dependent context
    case depressiveDisorder
    case anxietyDisorder
    case bipolarDisorder
    case schizophrenia

    var id: String { rawValue }

    var label: String {
        switch self {
        case .asthma: return "Asthma"
        case .copd: return "COPD"
        case .interstitialLungDisease: return "Interstitial lung disease"
        case .bronchiectasis: return "Bronchiectasis"
        case .cysticFibrosis: return "Cystic fibrosis"
        case .hypertension: return "Hypertension"
        case .hyperlipidemia: return "Hyperlipidemia"
        case .arrhythmia: return "Arrhythmia / atrial fibrillation"
        case .heartFailure: return "Heart failure"
        case .previousStroke: return "Previous stroke"
        case .peripheralVascularDisease: return "Peripheral vascular disease"
        case .coronaryHeartDisease: return "Coronary heart disease"
        case .diabetesMellitus: return "Diabetes mellitus"
        case .depressiveDisorder: return "Depressive disorder"
        case .anxietyDisorder: return "Anxiety disorder"
        case .bipolarDisorder: return "Bipolar disorder"
        case .schizophrenia: return "Schizophrenia"
        }
    }

    var category: HealthCategory {
        switch self {
        case .asthma, .copd, .interstitialLungDisease, .bronchiectasis, .cysticFibrosis:
            return .respiratory
        case .hypertension, .hyperlipidemia, .arrhythmia, .heartFailure,
             .previousStroke, .peripheralVascularDisease, .coronaryHeartDisease:
            return .cardiovascular
        case .diabetesMellitus:
            return .metabolic
        case .depressiveDisorder, .anxietyDisorder, .bipolarDisorder, .schizophrenia:
            return .mentalHealth
        }
    }

    /// Abstract tags used only for matching authoritative guidance text.
    /// A tag here means "some guidance source addresses this population",
    /// not "this condition carries a quantified risk".
    var guidanceTags: Set<GuidanceTag> {
        switch category {
        case .respiratory: return [.respiratoryCondition]
        case .cardiovascular: return [.cardiovascularCondition]
        case .metabolic: return [.metabolicCondition]
        case .mentalHealth: return []   // no exposure-specific AQI guidance mapped
        }
    }
}

enum HealthCategory: String, CaseIterable, Identifiable {
    case respiratory
    case cardiovascular
    case metabolic
    case mentalHealth

    var id: String { rawValue }

    var label: String {
        switch self {
        case .respiratory: return "Respiratory"
        case .cardiovascular: return "Cardiovascular"
        case .metabolic: return "Metabolic"
        case .mentalHealth: return "Mental health context"
        }
    }

    var note: String? {
        switch self {
        case .mentalHealth:
            return "Recorded as personal context. No air-quality guidance in this app is matched to these entries."
        default:
            return nil
        }
    }

    var conditions: [HealthCondition] {
        HealthCondition.allCases.filter { $0.category == self }
    }
}

/// Population tags that authoritative guidance documents actually address.
enum GuidanceTag: String, Codable {
    case respiratoryCondition
    case cardiovascularCondition
    case metabolicCondition
    case child
    case olderAdult
    case pregnancy
    case generalPopulation
}
