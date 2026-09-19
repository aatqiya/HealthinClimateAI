import Foundation

struct ParsedPlan {
    var draft: PlanDraft
    var missing: [String]
}

/// A local fallback, not a hosted language model. Never receives health fields.
struct LocalPlanAssistant: PlanAssisting {
    func extract(_ message: String, profiles: [UserProfile], now: Date = Date()) -> ParsedPlan {
        var draft = PlanDraft()
        var missing: [String] = []
        let lower = message.lowercased()
        if let profile = profiles.first(where: { lower.range(of: "\\b" + NSRegularExpression.escapedPattern(for: $0.name.lowercased()) + "\\b", options: .regularExpression) != nil }) { draft.profileID = profile.id }
        else { missing.append("Choose who this plan is for.") }
        let activities: [(String, String, ActivityType)] = [("soccer", "Soccer practice", .sports), ("doctor", "Doctor appointment", .appointment), ("appointment", "Appointment", .appointment), ("run", "Run", .exercise), ("dog", "Walk the dog", .dogWalk), ("commute", "Commute", .commute), ("walk", "Walk", .leisure)]
        if let activity = activities.first(where: { lower.range(of: "\\b" + $0.0 + "\\b", options: .regularExpression) != nil }) { draft.activityName = activity.1; draft.activityType = activity.2 }
        else { missing.append("Add an activity name.") }
        let calendar = Calendar.current
        var day = now
        var hasDate = false
        if lower.contains("tomorrow") { day = calendar.date(byAdding: .day, value: 1, to: now) ?? now; hasDate = true }
        else if lower.contains("today") { hasDate = true }
        else if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue), let match = detector.matches(in: message, range: NSRange(message.startIndex..., in: message)).first, let date = match.date { day = date; hasDate = true }
        if !hasDate { missing.append("Confirm the date.") }
        draft.startTime = day
        if let regex = try? NSRegularExpression(pattern: #"\bat\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?\b"#),
           let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let hourRange = Range(match.range(at: 1), in: lower), let rawHour = Int(lower[hourRange]) {
            let minute = Range(match.range(at: 2), in: lower).flatMap { Int(lower[$0]) } ?? 0
            let meridiem = Range(match.range(at: 3), in: lower).map { String(lower[$0]) } ?? ""
            var hour = rawHour
            if meridiem.hasPrefix("p") && hour < 12 { hour += 12 }
            if meridiem.hasPrefix("a") && hour == 12 { hour = 0 }
            if (0...23).contains(hour) && (0...59).contains(minute) {
                draft.startTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
                if meridiem.isEmpty && rawHour <= 12 { missing.append("Confirm AM or PM for the start time.") }
            } else { missing.append("Confirm the start time.") }
        } else { missing.append("Add a start time.") }
        if lower.contains("hour and a half") { draft.durationMinutes = 90 }
        else if let regex = try? NSRegularExpression(pattern: #"\b(?:for\s+)?(\d+(?:\.\d+)?)\s*(hours?|hrs?|minutes?|mins?)\b"#), let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)), let numberRange = Range(match.range(at: 1), in: lower), let number = Double(lower[numberRange]), let unitRange = Range(match.range(at: 2), in: lower) {
            draft.durationMinutes = max(15, min(480, Int(number * (lower[unitRange].hasPrefix("h") ? 60 : 1))))
        } else if lower.contains("for an hour") || lower.contains("for one hour") { draft.durationMinutes = 60 }
        else { missing.append("Confirm how long it lasts (currently 60 minutes).") }
        missing.append("Choose the exact address or place.")
        missing.append("Could the start time move earlier or later?")
        return .init(draft: draft, missing: missing)
    }
}
