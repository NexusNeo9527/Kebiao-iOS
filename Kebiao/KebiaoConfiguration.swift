import Foundation

enum KebiaoConfiguration {
    static let appGroupIdentifier = "group.com.example.kebiao"
    static let storageKey = "kebiao.courses.v1"
    static let semesterStartKey = "kebiao.semester.start.v1"
    static let collectionStorageKey = "kebiao.timetables.v2"
    static let syncMetadataKey = "kebiao.timetables.sync.v1"
    static let recoverySnapshotKey = "kebiao.timetables.recovery.v2"
    static let widgetKind = "KebiaoTodayWidget"
    static let scheduleURL = URL(string: "kebiao://schedule")!
}

enum ReminderPreferences {
    static let enabledKey = "kebiao.reminders.enabled"
}
