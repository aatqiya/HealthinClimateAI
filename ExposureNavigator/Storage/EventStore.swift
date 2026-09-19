import Foundation
import Observation

@Observable
final class EventStore {
    private(set) var events: [ActivityEvent] = []
    var storageError: String?
    private let fileURL: URL
    private var loadFailed = false
    init(directory: URL? = nil) {
        let directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = directory.appendingPathComponent("events.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: fileURL.path) { events = try JSONDecoder.appDecoder.decode([ActivityEvent].self, from: Data(contentsOf: fileURL)) }
        } catch { loadFailed = true; storageError = "Your saved events couldn't be opened. They have not been overwritten." }
    }
    var upcoming: [ActivityEvent] { events.filter { $0.endTime > Date() }.sorted { $0.selectedStart < $1.selectedStart } }
    @discardableResult func save(_ event: ActivityEvent) -> Bool {
        var updated = events
        if let index = updated.firstIndex(where: { $0.id == event.id }) { updated[index] = event } else { updated.append(event) }
        return persist(updated)
    }
    @discardableResult func delete(_ event: ActivityEvent) -> Bool { persist(events.filter { $0.id != event.id }) }
    @discardableResult func deleteEvents(for profileID: UUID) -> Bool { persist(events.filter { $0.profileID != profileID }) }
    private func persist(_ updated: [ActivityEvent]) -> Bool {
        guard !loadFailed else { storageError = "Existing data could not be read. Restart after recovering the saved file before making changes."; return false }
        do {
            try JSONEncoder.appEncoder.encode(updated).write(to: fileURL, options: [.atomic, .completeFileProtection])
            events = updated; storageError = nil; return true
        } catch { storageError = "Couldn't save events on this device. Please try again."; return false }
    }
}
