import Foundation

protocol PlaceSearching: Sendable {
    func lookup(_ query: String) async throws -> [ActivityLocation]
}

struct PlanningAgent {
    var parser: PlanAssisting = LocalPlanAssistant()
    var places: any PlaceSearching
    var environment: any EnvironmentalDataProviding

    func handle(_ message: String, session: PlanningSession, profiles: [UserProfile], now: Date, events: EventStore? = nil, temperatureUnit: String = "celsius") async -> PlanningSession {
        var session = session
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return session }
        session.messages.append(.user(trimmed))
        session.savedEvent = nil

        if Self.isRouteQuestion(trimmed) {
            session.messages.append(.assistant(Self.routeRefusal + "\n\n" + (session.phase == .recommending ? recommendationFollowUp(session, profiles: profiles, unit: temperatureUnit) : nextPrompt(for: &session, profiles: profiles))))
            return session
        }

        if (session.phase == .recommending || session.phase == .confirmed) && Self.isSave(trimmed) {
            return save(session, events: events, profiles: profiles, now: now, unit: temperatureUnit)
        }

        if session.phase == .recommending || session.phase == .confirmed {
            if Self.isKeepOriginal(trimmed) {
                session.selectedAlternative = nil
                session.messages.append(.assistant(keepOriginalReply(session, unit: temperatureUnit)))
                return session
            }
            if let alternative = matchAlternative(trimmed, session: session) {
                session.selectedAlternative = alternative
                session.messages.append(.assistant(selectedAlternativeReply(alternative, session: session, unit: temperatureUnit)))
                return session
            }
        }

        if !session.placeCandidates.isEmpty, let location = matchPlaceCandidate(trimmed, session: session) {
            return await selectPlace(location, session: session, profiles: profiles, now: now, temperatureUnit: temperatureUnit)
        }

        let parsed = parser.extract(trimmed, profiles: profiles, now: now)
        applyParsedSlots(parsed, to: &session)
        applyFlexibility(trimmed, to: &session)
        applyDurationAcknowledgement(trimmed, to: &session)

        if session.draft.location == nil, let query = placeQuery(trimmed, session: session, profiles: profiles, captured: parsed.captured) {
            return await searchPlaces(query, session: session, profiles: profiles, now: now, temperatureUnit: temperatureUnit)
        }

        if readyToAnalyze(session, profiles: profiles, now: now) {
            return await analyze(session, profiles: profiles, now: now, temperatureUnit: temperatureUnit)
        }

        session.phase = .collecting
        session.messages.append(.assistant(nextPrompt(for: &session, profiles: profiles)))
        return session
    }

    func selectPlace(_ location: ActivityLocation, session: PlanningSession, profiles: [UserProfile], now: Date, temperatureUnit: String = "celsius") async -> PlanningSession {
        var session = session
        session.draft.location = location
        session.draft.addressQuery = location.name
        session.knowledge.place = true
        session.placeCandidates = []
        session.awaiting.removeAll { $0 == .place || $0 == .placeChoice }
        if readyToAnalyze(session, profiles: profiles, now: now) {
            return await analyze(session, profiles: profiles, now: now, temperatureUnit: temperatureUnit)
        }
        session.phase = .collecting
        session.messages.append(.assistant("I'll use \(location.name). \(nextPrompt(for: &session, profiles: profiles))"))
        return session
    }

    func chooseAlternative(_ alternative: Alternative?, session: PlanningSession, temperatureUnit: String = "celsius") -> PlanningSession {
        var session = session
        session.selectedAlternative = alternative
        if let alternative {
            session.messages.append(.assistant(selectedAlternativeReply(alternative, session: session, unit: temperatureUnit)))
        } else {
            session.messages.append(.assistant(keepOriginalReply(session, unit: temperatureUnit)))
        }
        return session
    }

    func save(_ session: PlanningSession, events: EventStore?, profiles: [UserProfile], now: Date, unit: String) -> PlanningSession {
        var session = session
        guard let plan = session.lastPlan ?? session.draft.activityPlan(), profiles.contains(where: { $0.id == plan.profileID }) else {
            session.messages.append(.assistant("I still need a complete plan before saving. " + nextPrompt(for: &session, profiles: profiles)))
            return session
        }
        guard let events else {
            session.messages.append(.assistant("Use Save below, or review every field in Schedule."))
            return session
        }
        let assessment = session.selectedAlternative?.assessment ?? session.lastResult?.original
        let selectedStart = assessment?.start ?? plan.startTime
        var snapshot: ExposureSnapshot?
        if let result = session.lastResult, let series = session.lastSeries {
            snapshot = ExposureSnapshot(sourceRetrievedAt: series.fetchedAt, sourceMeasurementUpdatedAt: series.sourceUpdatedAt, analyzedAt: now, source: series.source, sourceUpdatedAt: series.fetchedAt, originalStart: plan.startTime, selectedStart: selectedStart, pm25Mean: (assessment ?? result.original).metric(.pm25)?.meanConcentration, apparentTemperatureC: (assessment ?? result.original).metric(.heat)?.meanConcentration, reductionPercent: session.selectedAlternative?.reductionPercent(for: .pm25))
        }
        let old = session.draft.editingEventID.flatMap { id in events.events.first { $0.id == id } }
        let event = ActivityEvent(id: old?.id ?? UUID(), plan: plan, selectedStart: selectedStart, selectedRoute: session.draft.selectedRoute, analysis: snapshot, source: old?.source ?? .exposureNavigator, createdAt: old?.createdAt ?? now)
        guard events.save(event) else {
            session.messages.append(.assistant(events.storageError ?? "Couldn't save that plan on this device."))
            return session
        }
        session.savedEvent = event
        session.phase = .confirmed
        let when = PlanningFormat.time(selectedStart, at: plan.location)
        session.messages.append(.assistant("Saved \(plan.activityName) at \(when). Health details stay on the profile and are not copied into the event. Review in Schedule or open it from Calendar."))
        return session
    }

    private func searchPlaces(_ query: String, session: PlanningSession, profiles: [UserProfile], now: Date, temperatureUnit: String) async -> PlanningSession {
        var session = session
        session.draft.addressQuery = query
        session.messages.append(.progress("Looking up that place…"))
        do {
            let found = try await places.lookup(query)
            session.placeCandidates = found
            if found.count == 1 {
                return await selectPlace(found[0], session: session, profiles: profiles, now: now, temperatureUnit: temperatureUnit)
            }
            session.awaiting = [.placeChoice]
            session.phase = .collecting
            let lines = found.enumerated().map { "\($0.offset + 1). \($0.element.name)" + ($0.element.formattedAddress.isEmpty ? "" : " — \($0.element.formattedAddress)") }.joined(separator: "\n")
            session.messages.append(.assistant("I found a few matches. Reply with a number or the place name.\n\n\(lines)"))
            return session
        } catch {
            session.placeCandidates = []
            session.awaiting = [.place]
            session.messages.append(.assistant("I couldn't find that place. Add a city or street address and try again."))
            return session
        }
    }

    private func analyze(_ session: PlanningSession, profiles: [UserProfile], now: Date, temperatureUnit: String) async -> PlanningSession {
        var session = session
        guard session.draft.location != nil, let plan = session.draft.activityPlan() else {
            session.phase = .collecting
            session.messages.append(.assistant(nextPrompt(for: &session, profiles: profiles)))
            return session
        }
        guard plan.startTime > now else {
            session.phase = .collecting
            session.knowledge.date = false
            session.knowledge.time = false
            session.messages.append(.assistant("That start time is in the past. Choose a future date and time."))
            return session
        }
        session.phase = .analyzing
        session.lastPlan = plan
        session.selectedAlternative = nil
        session.messages.append(.progress("Checking the \(PlanningFormat.time(plan.startTime, at: plan.location)) forecast…"))
        do {
            let series = try await environment.fetchConditions(latitude: plan.location.latitude, longitude: plan.location.longitude, range: Self.analysisRange(for: plan))
            session.environmentFetches += 1
            let result = CounterfactualEngine.evaluate(plan: plan, series: series, now: now)
            guard !result.original.metrics.isEmpty else {
                session.phase = .collecting
                session.messages.append(.assistant("There isn't enough published data covering this activity window to model exposure. You can change the time or save without analysis from Schedule."))
                return session
            }
            session.lastResult = result
            session.lastSeries = series
            let profile = profiles.first { $0.id == plan.profileID }
            session.lastGuidance = profile.map { GuidanceLibrary.items(profile: $0, plan: plan, pm25Mean: result.original.metric(.pm25)?.meanConcentration, apparentTemperatureC: result.original.metric(.heat)?.meanConcentration) } ?? []
            session.phase = .recommending
            session.awaiting = []
            session.messages.append(.assistant(recommendation(session, profiles: profiles, unit: temperatureUnit)))
            return session
        } catch {
            session.phase = .collecting
            session.messages.append(.assistant((error as? LocalizedError)?.errorDescription ?? "Couldn't check the forecast. Try again, or review the plan in Schedule."))
            return session
        }
    }

    private func applyParsedSlots(_ parsed: ParsedPlan, to session: inout PlanningSession) {
        let calendar = Calendar.current
        if parsed.captured.profile { session.draft.profileID = parsed.draft.profileID; session.knowledge.profile = true }
        if parsed.captured.activity {
            session.draft.activityName = parsed.draft.activityName
            session.draft.activityType = parsed.draft.activityType
            session.knowledge.activity = true
        }
        if parsed.captured.date || parsed.captured.time {
            let existing = session.draft.startTime
            var next = parsed.draft.startTime
            if parsed.captured.date && !parsed.captured.time {
                let time = calendar.dateComponents([.hour, .minute, .second], from: session.knowledge.time ? existing : parsed.draft.startTime)
                next = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: parsed.draft.startTime) ?? parsed.draft.startTime
            } else if parsed.captured.time && !parsed.captured.date && session.knowledge.date {
                let time = calendar.dateComponents([.hour, .minute], from: parsed.draft.startTime)
                next = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: existing) ?? parsed.draft.startTime
            }
            session.draft.startTime = next
            if parsed.captured.date { session.knowledge.date = true }
            if parsed.captured.time { session.knowledge.time = true }
        }
        if parsed.captured.duration {
            session.draft.durationMinutes = parsed.draft.durationMinutes
            session.knowledge.duration = true
        }
        if parsed.captured.time {
            session.knowledge.timeMeridiem = !parsed.missing.contains(where: { $0.contains("AM or PM") })
        } else if parsed.missing.contains(where: { $0.contains("AM or PM") }) {
            session.knowledge.timeMeridiem = false
        }
    }

    private func applyFlexibility(_ message: String, to session: inout PlanningSession) {
        let lower = message.lowercased()
        if let flexibility = Self.parseFlexibility(lower, awaiting: session.awaiting) {
            session.draft.flexibility = flexibility
            session.knowledge.flexibility = true
            if flexibility == .flexible {
                session.draft.earliestStart = session.draft.startTime.addingTimeInterval(-3600)
                session.draft.latestStart = session.draft.startTime.addingTimeInterval(3600)
            } else {
                session.draft.earliestStart = nil
                session.draft.latestStart = nil
            }
        } else if session.awaiting.contains(.flexibility) {
            if Self.isAffirmative(lower) {
                session.draft.flexibility = .oneHour
                session.knowledge.flexibility = true
            } else if Self.isNegative(lower) || lower.contains("fixed") {
                session.draft.flexibility = .fixed
                session.knowledge.flexibility = true
            }
        }
    }

    private func applyDurationAcknowledgement(_ message: String, to session: inout PlanningSession) {
        let lower = message.lowercased()
        if session.awaiting.contains(.duration) && Self.isAffirmative(lower) && Self.parseFlexibility(lower, awaiting: session.awaiting) == nil {
            session.knowledge.duration = true
        }
    }

    private func readyToAnalyze(_ session: PlanningSession, profiles: [UserProfile], now: Date) -> Bool {
        guard session.placeCandidates.isEmpty else { return false }
        guard session.knowledge.profile, session.draft.profileID != nil, profiles.contains(where: { $0.id == session.draft.profileID }) else { return false }
        guard session.knowledge.activity, !session.draft.activityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard session.knowledge.date, session.knowledge.time, session.knowledge.timeMeridiem else { return false }
        guard session.knowledge.place, session.draft.location != nil else { return false }
        guard session.knowledge.duration, session.knowledge.flexibility else { return false }
        guard session.draft.activityPlan() != nil else { return false }
        guard session.draft.startTime > now else { return false }
        return true
    }

    private func missingSlots(_ session: PlanningSession, profiles: [UserProfile]) -> [PlanningSlot] {
        var slots: [PlanningSlot] = []
        if !session.knowledge.profile || session.draft.profileID == nil || !profiles.contains(where: { $0.id == session.draft.profileID }) { slots.append(.profile) }
        if !session.knowledge.activity || session.draft.activityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { slots.append(.activity) }
        if !session.knowledge.date { slots.append(.date) }
        if !session.knowledge.time || !session.knowledge.timeMeridiem { slots.append(.time) }
        if !session.knowledge.place || session.draft.location == nil { slots.append(session.placeCandidates.isEmpty ? .place : .placeChoice) }
        if !session.knowledge.duration { slots.append(.duration) }
        if !session.knowledge.flexibility { slots.append(.flexibility) }
        return slots
    }

    private func nextPrompt(for session: inout PlanningSession, profiles: [UserProfile]) -> String {
        let missing = missingSlots(session, profiles: profiles)
        if missing == [.flexibility] {
            session.awaiting = [.flexibility]
            return "Could the start time move earlier or later? I need a window to compare safer times. You can say the time is fixed, up to 30 minutes, up to 1 hour, or flexible."
        }
        let ask = Array(missing.prefix(2))
        session.awaiting = ask
        let names = ask.map { slotPrompt($0, session: session, profiles: profiles) }
        if names.count == 2 { return "\(names[0]) \(names[1])" }
        return names.first ?? "Tell me a bit more about the plan."
    }

    private func slotPrompt(_ slot: PlanningSlot, session: PlanningSession, profiles: [UserProfile]) -> String {
        switch slot {
        case .profile:
            let names = profiles.map(\.name)
            return names.isEmpty ? "Who is this for? Create a profile first." : "Who is this for — \(list(names))?"
        case .activity: return "What activity are you planning?"
        case .date: return "Which date should I use?"
        case .time: return session.knowledge.time && !session.knowledge.timeMeridiem ? "Is that AM or PM?" : "What start time? Include AM or PM if needed."
        case .place: return "Where will this happen? I'll search for an exact place."
        case .placeChoice: return "Which of those places should I use?"
        case .duration: return "How long does it last? I can use \(session.draft.durationMinutes) minutes if that sounds right."
        case .flexibility: return "Could the start time move earlier or later?"
        }
    }

    private func recommendation(_ session: PlanningSession, profiles: [UserProfile], unit: String) -> String {
        guard let plan = session.lastPlan, let result = session.lastResult else { return "I checked the forecast." }
        let who = profiles.first { $0.id == plan.profileID }?.name ?? "this profile"
        let when = PlanningFormat.time(plan.startTime, at: plan.location)
        let until = PlanningFormat.time(plan.endTime, at: plan.location)
        var lines = ["Here's what the forecast shows for \(who)'s \(plan.activityName) at \(plan.location.name) from \(when) to \(until)."]
        if let pm25 = result.original.metric(.pm25) {
            lines.append("Fine particle pollution: \(Int(pm25.meanConcentration.rounded())) µg/m³.")
        } else {
            lines.append("Fine particle pollution is unavailable for this window.")
        }
        if let heat = result.original.metric(.heat) {
            lines.append("Feels like \(PlanningFormat.temperature(heat.meanConcentration, unit: unit)).")
        }
        if plan.constraints.timeFlexibility == .fixed {
            lines.append("The time is fixed, so I didn't compare other starts.")
        } else if result.alternatives.isEmpty {
            if result.primaryPollutant == nil {
                lines.append("There isn't enough complete particle data to compare times reliably.")
            } else {
                lines.append("No time I checked showed at least 10% lower modeled particle exposure. That display threshold is not a health threshold.")
            }
        } else {
            lines.append("Times with lower modeled particle exposure:")
            for alternative in result.alternatives {
                if case .timeShift(let minutes) = alternative.change {
                    let label = minutes > 0 ? "Start \(minutes) minutes later" : "Start \(-minutes) minutes earlier"
                    let percent = alternative.reductionPercent(for: .pm25).map { "\(Int($0.rounded()))% lower modeled fine particle exposure" } ?? ""
                    lines.append("• \(label) (\(PlanningFormat.time(alternative.assessment.start, at: plan.location))) — \(percent)")
                }
            }
        }
        for item in session.lastGuidance {
            lines.append("\(item.title): \(item.body)")
        }
        lines.append(Self.routeRefusal)
        lines.append("You can use a listed time, keep the original, save this plan, or change a detail.")
        return lines.joined(separator: "\n\n")
    }

    private func recommendationFollowUp(_ session: PlanningSession, profiles: [UserProfile], unit: String) -> String {
        if let best = session.lastResult?.bestMeaningful, let plan = session.lastPlan, case .timeShift(let minutes) = best.change {
            let percent = best.reductionPercent(for: .pm25).map { "\(Int($0.rounded()))%" } ?? "a modeled"
            return "A safer comparison I can make is start time. \(minutes > 0 ? "Starting \(minutes) minutes later" : "Starting \(-minutes) minutes earlier") is \(percent) lower modeled particle exposure than \(PlanningFormat.time(plan.startTime, at: plan.location))."
        }
        _ = profiles
        _ = unit
        return "I can still compare start times when you give a flexibility window, or save the original plan."
    }

    private func keepOriginalReply(_ session: PlanningSession, unit: String) -> String {
        guard let plan = session.lastPlan else { return "I'll keep the original start time. Say save when you want it on the calendar." }
        _ = unit
        return "I'll keep \(PlanningFormat.time(plan.startTime, at: plan.location)). Say save when you want it on the calendar."
    }

    private func selectedAlternativeReply(_ alternative: Alternative, session: PlanningSession, unit: String) -> String {
        let location = session.lastPlan?.location
        let when = location.map { PlanningFormat.time(alternative.assessment.start, at: $0) } ?? alternative.assessment.start.formatted(date: .omitted, time: .shortened)
        let percent = alternative.reductionPercent(for: .pm25).map { " (\(Int($0.rounded()))% lower modeled particle exposure)" } ?? ""
        _ = unit
        return "I'll use \(when)\(percent). Say save when you want it on the calendar, or change another detail."
    }

    private func matchAlternative(_ message: String, session: PlanningSession) -> Alternative? {
        guard let result = session.lastResult, !result.alternatives.isEmpty else { return nil }
        let lower = message.lowercased()
        if lower.contains("best") || (lower.contains("safer") && lower.contains("time")) { return result.bestMeaningful }
        if lower.contains("earlier") { return result.alternatives.min(by: { $0.assessment.start < $1.assessment.start }) }
        if lower.range(of: #"\blater\b"#, options: .regularExpression) != nil { return result.alternatives.max(by: { $0.assessment.start < $1.assessment.start }) }
        if let match = lower.range(of: #"\b(?:option|choice)\s*(\d+)\b"#, options: .regularExpression), let number = Int(lower[match].filter(\.isNumber)), result.alternatives.indices.contains(number - 1) {
            return result.alternatives[number - 1]
        }
        if let location = session.lastPlan?.location {
            for alternative in result.alternatives {
                let label = PlanningFormat.time(alternative.assessment.start, at: location).lowercased()
                if lower.contains(label) { return alternative }
                let hour = Calendar.current.component(.hour, from: alternative.assessment.start)
                let hour12 = hour % 12 == 0 ? 12 : hour % 12
                if lower.contains("\(hour12)") && ((hour >= 12 && (lower.contains("pm") || lower.contains("p.m"))) || (hour < 12 && (lower.contains("am") || lower.contains("a.m"))) || lower.contains("\(hour12):")) {
                    return alternative
                }
            }
        }
        return nil
    }

    private func matchPlaceCandidate(_ message: String, session: PlanningSession) -> ActivityLocation? {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = Int(trimmed), session.placeCandidates.indices.contains(index - 1) { return session.placeCandidates[index - 1] }
        let lower = trimmed.lowercased()
        return session.placeCandidates.first { $0.name.lowercased() == lower || $0.name.lowercased().contains(lower) || lower.contains($0.name.lowercased()) }
    }

    private func placeQuery(_ message: String, session: PlanningSession, profiles: [UserProfile], captured: ParsedFields) -> String? {
        if let nearby = Self.nearbyPlace(in: message) { return nearby }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.looksLikeAddress(trimmed) && !Self.isDurationOnly(trimmed) && !Self.isTimeOnly(trimmed) { return trimmed }
        guard session.awaiting.contains(.place), session.draft.location == nil else { return nil }
        if captured.profile || captured.date || captured.duration || captured.time { return nil }
        if profiles.contains(where: { trimmed.compare($0.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) { return nil }
        if Self.parseFlexibility(trimmed.lowercased(), awaiting: session.awaiting) != nil { return nil }
        if Self.isDurationOnly(trimmed) || Self.isDateOnly(trimmed) || Self.isTimeOnly(trimmed) { return nil }
        if Self.isAffirmative(trimmed) || Self.isNegative(trimmed) || Self.isSave(trimmed) { return nil }
        return trimmed
    }

    private func list(_ names: [String]) -> String {
        guard names.count > 1 else { return names.first ?? "someone" }
        return names.dropLast().joined(separator: ", ") + ", or " + names.last!
    }

    static let routeRefusal = "I can't pick a cleaner path or rank nearby routes. The forecast is for this place, not each nearby trail."

    static func analysisRange(for plan: ActivityPlan) -> ClosedRange<Date> {
        switch plan.constraints.timeFlexibility {
        case .fixed:
            return plan.startTime...plan.endTime
        case .halfHour, .oneHour:
            let seconds = TimeInterval(plan.constraints.timeFlexibility.minutes * 60)
            return plan.startTime.addingTimeInterval(-seconds)...plan.endTime.addingTimeInterval(seconds)
        case .flexible:
            let start = plan.constraints.earliestStart ?? plan.startTime
            let end = (plan.constraints.latestStart ?? plan.startTime).addingTimeInterval(TimeInterval(plan.durationMinutes * 60))
            return start...end
        }
    }

    static func isRouteQuestion(_ message: String) -> Bool {
        let lower = message.lowercased()
        let mentionsRoute = lower.contains("route") || lower.contains("path") || lower.contains("trail") || lower.contains("which way")
        return mentionsRoute && (lower.contains("safer") || lower.contains("safest") || lower.contains("better") || lower.contains("clean") || lower.contains("which"))
    }

    static func isSave(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower == "save" || lower.hasPrefix("save ") || lower.contains("save it") || lower.contains("save this") || lower.contains("add it to") || lower.contains("put it on the calendar")
    }

    static func isKeepOriginal(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("keep original") || lower.contains("keep the original") || lower == "keep it" || (lower.contains("keep") && (lower.contains("original") || lower.contains("planned") || lower.contains("6")))
    }

    static func isAffirmative(_ message: String) -> Bool {
        ["yes", "yeah", "yep", "sure", "ok", "okay", "please", "that works"].contains(message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    static func isNegative(_ message: String) -> Bool {
        let lower = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["no", "nope", "fixed"].contains(lower) || lower.contains("can't move") || lower.contains("cannot move") || lower.contains("time is fixed")
    }

    static func isDurationOnly(_ message: String) -> Bool {
        message.range(of: #"^\s*(?:for\s+)?(\d+(?:\.\d+)?)\s*(hours?|hrs?|minutes?|mins?)\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func isDateOnly(_ message: String) -> Bool {
        let lower = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["today", "tomorrow"].contains(lower)
    }

    static func isTimeOnly(_ message: String) -> Bool {
        message.range(of: #"^\s*(?:at\s+)?\d{1,2}(?::\d{2})?\s*(am|pm|a\.m\.|p\.m\.)?\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func looksLikeAddress(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("street") || lower.contains(" st") || lower.contains("ave") || lower.contains("park") || lower.contains("field") || lower.contains(",")
    }

    static func nearbyPlace(in message: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)\b(?:near|around)\s+(.+)$"#),
              let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
              let range = Range(match.range(at: 1), in: message) else { return nil }
        let value = message[range].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || isTimeOnly(value) ? nil : value
    }

    static func parseFlexibility(_ lower: String, awaiting: [PlanningSlot]) -> TimeFlexibility? {
        if lower.contains("flexible") || lower.contains("whenever") || lower.contains("any time") || lower.contains("anytime") { return .flexible }
        if lower.contains("time is fixed") || lower.contains("can't move") || lower.contains("cannot move") || lower.contains("no flexibility") { return .fixed }
        let window = lower.contains("up to") || lower.contains("earlier or later") || lower.contains("earlier/later") || awaiting.contains(.flexibility)
        if window && (lower.contains("30 minute") || lower.contains("half hour") || lower.contains("half-hour") || lower.contains("half an hour")) { return .halfHour }
        if window && (lower.contains("1 hour") || lower.contains("one hour") || lower.contains("an hour")) { return .oneHour }
        if lower.contains("up to an hour") || lower.contains("up to 1 hour") || lower.contains("an hour earlier") { return .oneHour }
        return nil
    }
}

enum PlanningFormat {
    static func time(_ date: Date, at location: ActivityLocation) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.timeZone = location.timeZone
        return formatter.string(from: date)
    }

    static func temperature(_ celsius: Double?, unit: String) -> String {
        guard let celsius else { return "—" }
        return "\(Int((unit == "fahrenheit" ? celsius * 9 / 5 + 32 : celsius).rounded()))°\(unit == "fahrenheit" ? "F" : "C")"
    }
}
