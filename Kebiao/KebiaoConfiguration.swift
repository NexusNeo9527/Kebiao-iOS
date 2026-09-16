import Foundation

enum KebiaoConfiguration {
    static let storageKey = "kebiao.courses.v1"
    static let scheduleURL = URL(string: "kebiao://schedule")!
}

enum ReminderPreferences {
    static let enabledKey = "kebiao.reminders.enabled"
}
