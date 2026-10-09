import Foundation
import UserNotifications

actor ReminderScheduler {
    static let shared = ReminderScheduler()
    private let center = UNUserNotificationCenter.current()
    private let identifierPrefix = "kebiao.course."
    private var generation = 0
    private var queue: Task<Void, Never>?

    func requestAuthorizationAndReschedule(courses: [Course]) async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            UserDefaults.standard.set(granted, forKey: ReminderPreferences.enabledKey)
            if granted { await reschedule(courses: courses) }
            return granted
        } catch {
            await disable()
            return false
        }
    }

    func disable() async {
        generation += 1
        UserDefaults.standard.set(false, forKey: ReminderPreferences.enabledKey)
        await removeCourseRequests()
    }

    func reschedule(courses: [Course]) async {
        generation += 1
        let revision = generation
        let previous = queue
        let task = Task {
            await previous?.value
            await self.apply(courses: courses, revision: revision)
        }
        queue = task
        await task.value
    }

    private func removeCourseRequests() async {
        let requests = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) })
    }

    private func apply(courses: [Course], revision: Int) async {
        guard revision == generation, UserDefaults.standard.bool(forKey: ReminderPreferences.enabledKey) else { return }
        let settings = await center.notificationSettings()
        guard revision == generation, settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        await removeCourseRequests()
        guard revision == generation else { return }
        for reminder in ScheduleEngine.reminders(in: courses, after: .now) {
            guard revision == generation, UserDefaults.standard.bool(forKey: ReminderPreferences.enabledKey) else { return }
            let course = reminder.occurrence.course
            let content = UNMutableNotificationContent()
            content.title = "还有 \(course.reminderMinutesBefore ?? 10) 分钟上课"
            content.body = "\(course.name) · \(course.location)"
            content.sound = .default
            content.userInfo = ["url": KebiaoConfiguration.scheduleURL.absoluteString]
            var parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
            parts.timeZone = Calendar.current.timeZone
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let identifier = "\(identifierPrefix)\(course.id.uuidString).\(Int(reminder.occurrence.startDate.timeIntervalSince1970))"
            try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            if revision != generation {
                center.removePendingNotificationRequests(withIdentifiers: [identifier])
                return
            }
        }
    }
}
