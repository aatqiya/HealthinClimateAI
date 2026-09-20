import HealthKit
import Observation

/// Requests Apple Health read permission only. No HealthKit data is read or stored yet —
/// this exists so a future feature can ask for consent without a second permission prompt.
@Observable @MainActor
final class HealthKitService {
    static let isAvailable = HKHealthStore.isHealthDataAvailable()
    static let readTypes: Set<HKObjectType> = {
        var types: Set<HKObjectType> = []
        if let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) { types.insert(heartRate) }
        if let respiratoryRate = HKObjectType.quantityType(forIdentifier: .respiratoryRate) { types.insert(respiratoryRate) }
        return types
    }()
    private let store = HKHealthStore()
    var requested: Bool
    var errorMessage: String?

    init() { requested = UserDefaults.standard.bool(forKey: "appleHealthRequested") }

    func requestAccess() async {
        guard Self.isAvailable else { errorMessage = "Apple Health isn't available on this device."; return }
        do {
            try await store.requestAuthorization(toShare: [], read: Self.readTypes)
            requested = true
            UserDefaults.standard.set(true, forKey: "appleHealthRequested")
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't request Apple Health access. Please try again."
        }
    }
}
