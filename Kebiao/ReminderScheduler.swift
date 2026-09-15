import Foundation
import UserNotifications

actor ReminderScheduler {
    static let shared = ReminderScheduler()
    private let center = UNUserNotificationCenter.current()
    private let identifierPrefix = "kebiao.course."

    func requestAuthorizationAndReschedule(courses: [Course]) async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            UserDefaults.standard.set(granted, forKey: ReminderPreferences.enabledKey)
            if granted {
                await reschedule(courses: courses)
            }
            return granted
        } catch {
            UserDefaults.standard.set(false, forKey: ReminderPreferences.enabledKey)
            return false
        }
    }

    func disable() {
        UserDefaults.standard.set(false, forKey: ReminderPreferences.enabledKey)
        center.removeAllPendingNotificationRequests()
    }

    func reschedule(courses: [Course]) async {
        guard UserDefaults.standard.bool(forKey: ReminderPreferences.enabledKey) else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        center.removeAllPendingNotificationRequests()
        var requests: [UNNotificationRequest] = []

        for course in courses {
            guard let leadTime = course.reminderMinutesBefore else { continue }
            for day in course.weekdays.sorted(by: { $0.weekIndex < $1.weekIndex }) {
                let triggerParts = reminderDateComponents(day: day, startMinutes: course.resolvedStartTimeMinutes, leadTime: leadTime)
                let content = UNMutableNotificationContent()
                content.title = "还有 \(leadTime) 分钟上课"
                content.body = "\(course.name) · \(course.location)"
                content.sound = .default
                content.userInfo = ["url": KebiaoConfiguration.scheduleURL.absoluteString]
                let trigger = UNCalendarNotificationTrigger(dateMatching: triggerParts, repeats: true)
                let identifier = "\(identifierPrefix)\(course.id.uuidString).\(day.rawValue)"
                requests.append(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            }
        }

        for request in requests.prefix(60) {
            try? await center.add(request)
        }
    }

    private func reminderDateComponents(day: Weekday, startMinutes: Int, leadTime: Int) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let reference = Date(timeIntervalSince1970: 345_600)
        let weekDate = day.date(inWeekContaining: reference, calendar: calendar)
        let start = calendar.date(byAdding: .minute, value: startMinutes - leadTime, to: weekDate) ?? weekDate
        return calendar.dateComponents([.weekday, .hour, .minute], from: start)
    }
}
