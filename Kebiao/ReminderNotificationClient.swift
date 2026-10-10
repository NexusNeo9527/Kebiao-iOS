import Foundation
import UserNotifications

struct ReminderNotificationRequest: Sendable, Equatable {
    let identifier: String
    let title: String
    let body: String
    let fireDate: Date
    let timeZoneIdentifier: String
}

/// Value types keep system notification objects out of the scheduling actor and test fakes.
struct ReminderNotificationClient: Sendable {
    var requestAuthorization: @Sendable () async throws -> Bool
    var settings: @Sendable () async -> ReminderNotificationSettings
    var pending: @Sendable () async -> [PendingReminderNotification]
    var add: @Sendable (ReminderNotificationRequest) async throws -> Void
    var remove: @Sendable ([String]) async -> Void

    static var system: Self {
        Self(requestAuthorization: {
            try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }, settings: {
            let value = await UNUserNotificationCenter.current().notificationSettings()
            return ReminderNotificationSettings(authorization: authorization(value.authorizationStatus),
                alerts: presentation(value.alertSetting), sound: presentation(value.soundSetting))
        }, pending: {
            await UNUserNotificationCenter.current().pendingNotificationRequests().map {
                PendingReminderNotification(identifier: $0.identifier,
                    nextTriggerDate: ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
                        ?? ($0.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate())
            }
        }, add: { request in
            let content = UNMutableNotificationContent()
            content.title = request.title
            content.body = request.body
            content.sound = .default
            content.userInfo = ["url": KebiaoConfiguration.scheduleURL.absoluteString]
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: request.timeZoneIdentifier) ?? .current
            var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: request.fireDate)
            parts.timeZone = calendar.timeZone
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger))
        }, remove: { identifiers in
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        })
    }

    private static func authorization(_ value: UNAuthorizationStatus) -> ReminderAuthorization {
        switch value {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized: .authorized
        case .provisional: .provisional
        case .ephemeral: .ephemeral
        @unknown default: .unknown
        }
    }

    private static func presentation(_ value: UNNotificationSetting) -> ReminderPresentationSetting {
        switch value {
        case .enabled: .enabled
        case .disabled: .disabled
        case .notSupported: .unsupported
        @unknown default: .unknown
        }
    }
}
