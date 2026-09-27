import Foundation

enum KebiaoConfiguration {
    static let appGroupIdentifier = "group.com.example.kebiao"
    static let storageKey = "kebiao.courses.v1"
    static let widgetKind = "KebiaoTodayWidget"
    static let scheduleURL = URL(string: "kebiao://schedule")!
}

enum ReminderPreferences {
    static let enabledKey = "kebiao.reminders.enabled"
}
