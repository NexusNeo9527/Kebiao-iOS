import Foundation

actor ReminderScheduler {
    static let shared = ReminderScheduler()
    private let client: ReminderNotificationClient
    private let preferences: UserDefaults
    private let timetableDefaults: UserDefaults?
    private let currentTimetable: (@Sendable (Timetable) -> Bool)?
    private let now: @Sendable () -> Date
    private let identifierPrefix = "kebiao.course."
    private var generation = 0
    private var authorizationGeneration = 0
    private var diagnosticsGeneration = 0
    private var queue: Task<Void, Never>?
    private var failures: [UUID: ReminderScheduleFailure] = [:]

    init(client: ReminderNotificationClient = .system, preferenceDefaults: UserDefaults = .standard,
         timetableDefaults: UserDefaults? = nil,
         currentTimetable: (@Sendable (Timetable) -> Bool)? = nil,
         now: @escaping @Sendable () -> Date = { .now }) {
        self.client = client
        self.preferences = preferenceDefaults
        self.timetableDefaults = timetableDefaults
        self.currentTimetable = currentTimetable
        self.now = now
    }

    func requestAuthorizationAndReschedule(courses: [Course]) async -> Bool {
        authorizationGeneration += 1
        let authorizationRevision = authorizationGeneration
        generation += 1
        do {
            let granted = try await client.requestAuthorization()
            guard authorizationRevision == authorizationGeneration else {
                return preferences.bool(forKey: ReminderPreferences.enabledKey)
            }
            preferences.set(granted, forKey: ReminderPreferences.enabledKey)
            if granted { await reschedule(courses: courses) }
            return granted
        } catch {
            guard authorizationRevision == authorizationGeneration else {
                return preferences.bool(forKey: ReminderPreferences.enabledKey)
            }
            await disable()
            return false
        }
    }

    func requestAuthorizationAndReschedule(timetable: Timetable) async -> Bool {
        guard isCurrent(timetable) else { return preferences.bool(forKey: ReminderPreferences.enabledKey) }
        authorizationGeneration += 1
        let authorizationRevision = authorizationGeneration
        generation += 1
        do {
            let granted = try await client.requestAuthorization()
            guard authorizationRevision == authorizationGeneration, isCurrent(timetable) else {
                return preferences.bool(forKey: ReminderPreferences.enabledKey)
            }
            preferences.set(granted, forKey: ReminderPreferences.enabledKey)
            if granted { await reschedule(timetable: timetable) }
            return granted
        } catch {
            guard authorizationRevision == authorizationGeneration, isCurrent(timetable) else {
                return preferences.bool(forKey: ReminderPreferences.enabledKey)
            }
            await disable()
            return false
        }
    }

    func disable() async {
        authorizationGeneration += 1
        generation += 1
        let revision = generation
        preferences.set(false, forKey: ReminderPreferences.enabledKey)
        let previous = queue
        // Cleanup participates in the same queue as additions. A suspended removal
        // cannot resume after a newer schedule has added requests with the same IDs.
        let task = Task {
            await previous?.value
            await self.removeCourseRequests(revision: revision)
        }
        queue = task
        await task.value
    }

    func reschedule(courses: [Course]) async {
        await enqueue(reminders: ScheduleEngine.reminders(in: courses, after: now()), calendar: .current)
    }

    func reschedule(timetable: Timetable) async {
        guard isCurrent(timetable) else { return }
        await enqueue(reminders: ScheduleEngine.reminders(in: timetable, after: now()), calendar: timetable.calendar, timetable: timetable)
    }

    /// A query belongs to one complete timetable snapshot and one scheduling generation.
    /// Returning nil leaves a newer UI query in control instead of publishing stale state.
    func diagnostics(timetable: Timetable) async -> ReminderDiagnostics? {
        guard isCurrent(timetable) else { return nil }
        diagnosticsGeneration += 1
        let queryRevision = diagnosticsGeneration
        let revision = generation
        let enabled = preferences.bool(forKey: ReminderPreferences.enabledKey)
        await queue?.value
        guard diagnosticsAreCurrent(queryRevision, revision, timetable, enabled) else { return nil }
        let settings = await client.settings()
        guard diagnosticsAreCurrent(queryRevision, revision, timetable, enabled) else { return nil }
        let pending = await client.pending()
        guard diagnosticsAreCurrent(queryRevision, revision, timetable, enabled) else { return nil }
        return ReminderDiagnostics.make(timetableID: timetable.id, appEnabled: enabled, settings: settings,
            pending: pending, recentFailure: failures[timetable.id], checkedAt: now())
    }

    private func diagnosticsAreCurrent(_ query: Int, _ revision: Int, _ timetable: Timetable, _ enabled: Bool) -> Bool {
        query == diagnosticsGeneration && revision == generation && isCurrent(timetable)
            && enabled == preferences.bool(forKey: ReminderPreferences.enabledKey)
    }

    static func notificationIdentifier(for occurrence: CourseOccurrence) -> String {
        "kebiao.course.\(occurrence.id)"
    }

    private func enqueue(reminders: [CourseReminder], calendar: Calendar, timetable: Timetable? = nil) async {
        guard isCurrent(timetable) else { return }
        generation += 1
        let revision = generation
        let previous = queue
        let task = Task {
            await previous?.value
            guard self.isCurrent(timetable) else { return }
            await self.apply(reminders: reminders, calendar: calendar, revision: revision, timetable: timetable)
        }
        queue = task
        await task.value
    }

    private func removeCourseRequests(revision: Int? = nil, timetable: Timetable? = nil) async {
        guard isCurrent(timetable) else { return }
        let requests = await client.pending()
        guard isCurrent(timetable), revision == nil || revision == generation else { return }
        await client.remove(requests.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) })
    }

    private func isCurrent(_ timetable: Timetable?) -> Bool {
        guard let timetable else { return true }
        if let currentTimetable { return currentTimetable(timetable) }
        let defaults = timetableDefaults ?? UserDefaults(suiteName: KebiaoConfiguration.appGroupIdentifier) ?? .standard
        guard let stored = defaults.object(forKey: KebiaoConfiguration.collectionStorageKey) else { return true }
        guard let data = stored as? Data else { return false }
        do {
            let collection = try JSONDecoder().decode(TimetableCollection.self, from: data)
            try collection.validate()
            return collection.activeTimetable == timetable
        } catch { return false }
    }

    private func apply(reminders: [CourseReminder], calendar: Calendar, revision: Int, timetable: Timetable? = nil) async {
        guard revision == generation, isCurrent(timetable), preferences.bool(forKey: ReminderPreferences.enabledKey) else { return }
        let settings = await client.settings()
        guard revision == generation, isCurrent(timetable), settings.authorization.allowsScheduling else { return }
        await removeCourseRequests(revision: revision, timetable: timetable)
        guard revision == generation, isCurrent(timetable) else { return }
        var failedMessages: [String] = []
        for reminder in reminders {
            guard revision == generation, isCurrent(timetable), preferences.bool(forKey: ReminderPreferences.enabledKey) else { return }
            let course = reminder.occurrence.course
            let identifier = Self.notificationIdentifier(for: reminder.occurrence)
            let request = ReminderNotificationRequest(identifier: identifier,
                title: "还有 \(course.reminderMinutesBefore ?? 10) 分钟上课",
                body: "\(course.name) · \(course.location)", fireDate: reminder.fireDate,
                timeZoneIdentifier: calendar.timeZone.identifier)
            do {
                try await client.add(request)
            } catch {
                failedMessages.append("\(course.name)：\(error.localizedDescription)")
            }
            if revision != generation || !isCurrent(timetable) || !preferences.bool(forKey: ReminderPreferences.enabledKey) {
                await client.remove([identifier])
                return
            }
        }
        guard revision == generation, isCurrent(timetable) else { return }
        let timetableID = timetable?.id ?? ScheduleEngine.legacyTimetableID
        if let firstFailure = failedMessages.first {
            failures[timetableID] = ReminderScheduleFailure(failedCount: failedMessages.count,
                attemptedCount: reminders.count, message: firstFailure, occurredAt: now())
        } else {
            failures[timetableID] = nil
        }
    }
}
