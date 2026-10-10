import Foundation

enum ReminderAuthorization: String, Sendable {
    case notDetermined, denied, authorized, provisional, ephemeral, unknown

    var allowsScheduling: Bool { [.authorized, .provisional, .ephemeral].contains(self) }

    var description: String {
        switch self {
        case .notDetermined: "尚未申请"
        case .denied: "已拒绝"
        case .authorized: "已允许"
        case .provisional: "临时授权（静默通知）"
        case .ephemeral: "短时授权"
        case .unknown: "未知"
        }
    }
}

enum ReminderPresentationSetting: String, Sendable {
    case enabled, disabled, unsupported, unknown

    var description: String {
        switch self {
        case .enabled: "已开启"
        case .disabled: "已关闭"
        case .unsupported: "不可用"
        case .unknown: "未知"
        }
    }
}

struct ReminderNotificationSettings: Sendable, Equatable {
    var authorization: ReminderAuthorization
    var alerts: ReminderPresentationSetting
    var sound: ReminderPresentationSetting
}

struct PendingReminderNotification: Sendable, Equatable {
    let identifier: String
    let nextTriggerDate: Date?
}

struct ReminderScheduleFailure: Sendable, Equatable {
    let failedCount: Int
    let attemptedCount: Int
    let message: String
    let occurredAt: Date
}

struct ReminderDiagnostics: Sendable, Equatable {
    let timetableID: UUID
    let appEnabled: Bool
    let settings: ReminderNotificationSettings
    let scheduledCount: Int
    let otherTimetableCount: Int
    let nextReminderDate: Date?
    let recentFailure: ReminderScheduleFailure?
    let checkedAt: Date

    static func make(timetableID: UUID, appEnabled: Bool, settings: ReminderNotificationSettings,
                     pending: [PendingReminderNotification], recentFailure: ReminderScheduleFailure?,
                     checkedAt: Date) -> Self {
        let prefix = "kebiao.course."
        let currentPrefix = "\(prefix)\(timetableID.uuidString)-"
        let courseRequests = pending.filter { $0.identifier.hasPrefix(prefix) }
        let currentRequests = courseRequests.filter { $0.identifier.hasPrefix(currentPrefix) }
        return Self(timetableID: timetableID, appEnabled: appEnabled, settings: settings,
                    scheduledCount: currentRequests.count,
                    otherTimetableCount: courseRequests.count - currentRequests.count,
                    nextReminderDate: currentRequests.compactMap(\.nextTriggerDate).min(),
                    recentFailure: recentFailure, checkedAt: checkedAt)
    }
}
