import EventKit
import EventKitUI
import SwiftUI
import Observation

struct ExternalCalendarEvent: Identifiable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var location: String?
    var calendarName: String
    var isAllDay: Bool
}

@Observable @MainActor
final class CalendarService {
    let store = EKEventStore()
    var connected = false
    var events: [ExternalCalendarEvent] = []
    var errorMessage: String?
    var loading = false
    private var displayedDate = Date()
    func connect(date: Date) async {
        loading = true; defer { loading = false }
        do {
            let granted = try await store.requestFullAccessToEvents()
            UserDefaults.standard.set(granted, forKey: "appleCalendarEnabled")
            guard granted else { errorMessage = "Calendar access wasn't granted. You can enable it in iOS Settings."; return }
            await refresh(date: date)
        } catch { errorMessage = "Couldn't connect Apple Calendar. Please try again." }
    }
    func refresh(date: Date) async {
        displayedDate = date
        connected = UserDefaults.standard.bool(forKey: "appleCalendarEnabled") && EKEventStore.authorizationStatus(for: .event) == .fullAccess
        guard connected else { events = []; return }
        guard let interval = Calendar.current.dateInterval(of: .month, for: date) else { return }
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
        events = store.events(matching: predicate).map { event in
            .init(id: "\(event.eventIdentifier ?? event.calendarItemIdentifier)-\(event.startDate.timeIntervalSince1970)", title: event.title ?? "Calendar event", start: event.startDate, end: event.endDate, location: event.location, calendarName: event.calendar.title, isAllDay: event.isAllDay)
        }.sorted { $0.start < $1.start }
        errorMessage = nil
    }
    func disconnect() { UserDefaults.standard.set(false, forKey: "appleCalendarEnabled"); connected = false; events = [] }
}

/// Apple shows its native editor. Nothing is exported until the user taps Save.
struct AppleCalendarExportView: UIViewControllerRepresentable {
    let event: ActivityEvent
    let store: EKEventStore
    let onFinish: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }
    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let editor = EKEventEditViewController()
        editor.eventStore = store
        let exported = EKEvent(eventStore: store)
        exported.title = event.plan.activityName
        exported.startDate = event.selectedStart
        exported.endDate = event.endTime
        exported.location = event.plan.location.formattedAddress
        exported.timeZone = event.plan.location.timeZone
        exported.calendar = store.defaultCalendarForNewEvents
        editor.event = exported
        editor.editViewDelegate = context.coordinator
        return editor
    }
    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}
    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) { onFinish() }
    }
}
