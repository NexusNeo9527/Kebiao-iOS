import Foundation
import UserNotifications

actor ReminderScheduler {
    static let shared = ReminderScheduler()
    private let center = UNUserNotificationCenter.current()
    private let identifierPrefix = "kebiao.course."
    private var generation = 0
    private var authorizationGeneration = 0
    private var queue: Task<Void, Never>?

    func requestAuthorizationAndReschedule(courses: [Course]) async -> Bool {
        authorizationGeneration += 1
        let authorizationRevision = authorizationGeneration
        generation += 1
        let revision = generation
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            guard authorizationRevision == authorizationGeneration else {
                return UserDefaults.standard.bool(forKey: ReminderPreferences.enabledKey)
            }
            UserDefaults.standard.set(granted, forKey: ReminderPreferences.enabledKey)
            if granted, revision == generation { await reschedule(courses: courses) }
            return granted
        } catch {
            guard authorizationRevision == authorizationGeneration else {
                return UserDefaults.standard.bool(forKey: ReminderPreferences.enabledKey)
            }
            await disable()
            return false
        }
    }

    func requestAuthorizationAndReschedule(timetable: Timetable) async -> Bool {
        authorizationGeneration += 1
        let authorizationRevision = authorizationGeneration
        generation += 1
        let revision = generation
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            guard authorizationRevision == authorizationGeneration else {
                return UserDefaults.standard.bool(forKey: ReminderPreferences.enabledKey)
            }
            UserDefaults.standard.set(granted, forKey: ReminderPreferences.enabledKey)
            if granted, revision == generation { await reschedule(timetable: timetable) }
            return granted
        } catch {
            guard authorizationRevision == authorizationGeneration else {
                return UserDefaults.standard.bool(forKey: ReminderPreferences.enabledKey)
            }
            await disable()
            return false
        }
    }

    func disable() async {
        authorizationGeneration += 1
        generation += 1
        UserDefaults.standard.set(false, forKey: ReminderPreferences.enabledKey)
        await removeCourseRequests()
    }

    func reschedule(courses: [Course]) async {
        await enqueue(reminders: ScheduleEngine.reminders(in: courses, after: .now), calendar: .current)
    }

    func reschedule(timetable: Timetable) async {
        await enqueue(reminders: ScheduleEngine.reminders(in: timetable, after: .now), calendar: timetable.calendar)
    }

    static func notificationIdentifier(for occurrence: CourseOccurrence) -> String {
        "kebiao.course.\(occurrence.id)"
    }

    private func enqueue(reminders: [CourseReminder], calendar: Calendar) async {
        generation += 1
        let revision = generation
        let previous = queue
        let task = Task {
            await previous?.value
            await self.apply(reminders: reminders, calendar: calendar, revision: revision)
        }
        queue = task
        await task.value
    }

    private func removeCourseRequests() async {
        let requests = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) })
    }

    private func apply(reminders: [CourseReminder], calendar: Calendar, revision: Int) async {
        guard revision == generation, UserDefaults.standard.bool(forKey: ReminderPreferences.enabledKey) else { return }
        let settings = await center.notificationSettings()
        guard revision == generation, settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        await removeCourseRequests()
        guard revision == generation else { return }
        for reminder in reminders {
            guard revision == generation, UserDefaults.standard.bool(forKey: ReminderPreferences.enabledKey) else { return }
            let course = reminder.occurrence.course
            let content = UNMutableNotificationContent()
            content.title = "还有 \(course.reminderMinutesBefore ?? 10) 分钟上课"
            content.body = "\(course.name) · \(course.location)"
            content.sound = .default
            content.userInfo = ["url": KebiaoConfiguration.scheduleURL.absoluteString]
            var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
            parts.timeZone = calendar.timeZone
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let identifier = Self.notificationIdentifier(for: reminder.occurrence)
            try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            if revision != generation {
                center.removePendingNotificationRequests(withIdentifiers: [identifier])
                return
            }
        }
    }
}
