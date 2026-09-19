import Foundation
import Observation

@Observable
final class ProfileStore {
    private(set) var profiles: [UserProfile] = []
    var storageError: String?
    var selectedProfileID: UUID? { didSet { UserDefaults.standard.set(selectedProfileID?.uuidString, forKey: "selectedProfileID") } }
    private let fileURL: URL
    private var loadFailed = false

    init(filename: String = "profiles-v2.json", directory: URL? = nil) {
        let directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = directory.appendingPathComponent(filename)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                profiles = try JSONDecoder.appDecoder.decode([UserProfile].self, from: Data(contentsOf: fileURL))
            }
        } catch { loadFailed = true; storageError = "Your saved profiles couldn't be opened. They have not been overwritten." }
        let saved = UUID(uuidString: UserDefaults.standard.string(forKey: "selectedProfileID") ?? "")
        selectedProfileID = profiles.contains(where: { $0.id == saved }) ? saved : profiles.first?.id
    }
    var selectedProfile: UserProfile? { profiles.first { $0.id == selectedProfileID } }
    func select(_ id: UUID) { if profiles.contains(where: { $0.id == id }) { selectedProfileID = id } }
    func add(_ profile: UserProfile) {
        if persist(profiles + [profile]) { selectedProfileID = profile.id }
    }
    func update(_ profile: UserProfile) {
        var updated = profiles
        guard let index = updated.firstIndex(where: { $0.id == profile.id }) else { return }
        updated[index] = profile; updated[index].updatedAt = Date(); _ = persist(updated)
    }
    func delete(_ profile: UserProfile) {
        if persist(profiles.filter { $0.id != profile.id }), selectedProfileID == profile.id { selectedProfileID = profiles.first?.id }
    }
    func addSampleProfiles() {
        if let existing = profiles.first(where: { $0.source == .synthetic && $0.name == "Maya" }) { select(existing.id); return }
        add(UserProfile(name: "Maya", relationship: .child, age: 12, homeZipCode: "10044", medicalConditions: ["Asthma"], source: .synthetic))
    }
    @discardableResult private func persist(_ updated: [UserProfile]) -> Bool {
        guard !loadFailed else { storageError = "Existing data could not be read. Restart after recovering the saved file before making changes."; return false }
        do {
            try JSONEncoder.appEncoder.encode(updated).write(to: fileURL, options: [.atomic, .completeFileProtection])
            profiles = updated; storageError = nil; return true
        } catch { storageError = "Couldn't save profiles on this device. Please try again."; return false }
    }
}
extension JSONEncoder { static var appEncoder: JSONEncoder { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; return encoder } }
extension JSONDecoder { static var appDecoder: JSONDecoder { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder } }
