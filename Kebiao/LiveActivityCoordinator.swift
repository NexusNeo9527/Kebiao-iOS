import ActivityKit
import Foundation
import Observation

enum LiveActivityPreferences {
    static let enabledKey = "kebiao.liveActivities.enabled"

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? true
    }
}

struct LiveActivityStatus {
    enum Phase { case idle, disabled, systemDenied, waiting, scheduled, starting, active, preview, failed }
    let phase: Phase
    let message: String
    var activityID: String? = nil
    var activityState: String? = nil
}

struct LiveActivityPlan {
    let nextOccurrence: CourseOccurrence?
    let occurrenceToDisplay: CourseOccurrence?

    static func make(courses: [Course], at now: Date, calendar: Calendar = .current) -> Self {
        let next = ScheduleEngine.currentOrUpcomingOccurrence(in: courses, at: now, calendar: calendar)
        return make(next: next, at: now, calendar: calendar)
    }

    static func make(timetable: Timetable, at now: Date) -> Self {
        make(next: ScheduleEngine.currentOrUpcomingOccurrence(in: timetable, at: now),
             at: now, calendar: timetable.calendar)
    }

    private static func make(next: CourseOccurrence?, at now: Date, calendar: Calendar) -> Self {
        let display = next.flatMap { occurrence -> CourseOccurrence? in
            if occurrence.startDate <= now { return occurrence }
            guard calendar.isDate(occurrence.startDate, inSameDayAs: now),
                  occurrence.startDate.timeIntervalSince(now) <= 6 * 60 * 60 else { return nil }
            return occurrence
        }
        return Self(nextOccurrence: next, occurrenceToDisplay: display)
    }

    static func scheduledStart(for occurrence: CourseOccurrence, calendar: Calendar = .current) -> Date {
        max(max(calendar.startOfDay(for: occurrence.startDate),
                occurrence.startDate.addingTimeInterval(-6 * 60 * 60)),
            occurrence.endDate.addingTimeInterval(-8 * 60 * 60))
    }
}

struct LiveActivityHandle {
    let id: String
    let attributes: ClassActivityAttributes
    let state: ActivityState
}

@MainActor
struct LiveActivityClient {
    var authorized: () -> Bool
    var activities: () -> [LiveActivityHandle]
    var request: (CourseOccurrence) throws -> LiveActivityHandle
    var end: (LiveActivityHandle) async -> Void
    var schedule: ((CourseOccurrence, Date) throws -> LiveActivityHandle)? = nil

    static var system: Self {
        var client = Self(
            authorized: { ActivityAuthorizationInfo().areActivitiesEnabled },
            activities: {
                Activity<ClassActivityAttributes>.activities.map {
                    LiveActivityHandle(id: $0.id, attributes: $0.attributes, state: $0.activityState)
                }
            },
            request: { occurrence in
                let attributes = Self.makeAttributes(for: occurrence)
                let content = ActivityContent(
                    state: ClassActivityAttributes.ContentState(updatedAt: .now),
                    staleDate: occurrence.endDate
                )
                let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
                return LiveActivityHandle(id: activity.id, attributes: attributes, state: activity.activityState)
            },
            end: { handle in
                if let activity = Activity<ClassActivityAttributes>.activities.first(where: { $0.id == handle.id }) {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
        )
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            client.schedule = { occurrence, start in
                let attributes = Self.makeAttributes(for: occurrence)
                let content = ActivityContent(
                    state: ClassActivityAttributes.ContentState(updatedAt: .now),
                    staleDate: occurrence.endDate
                )
                let alert = AlertConfiguration(title: "即将上课", body: "课程实时活动已开始，请查看课表。", sound: .default)
                let activity = try Activity.request(attributes: attributes, content: content, pushType: nil,
                    style: .standard, alertConfiguration: alert, start: start)
                return LiveActivityHandle(id: activity.id, attributes: attributes, state: activity.activityState)
            }
        }
#endif
        return client
    }

    private static func makeAttributes(for occurrence: CourseOccurrence) -> ClassActivityAttributes {
        let course = occurrence.course
        return ClassActivityAttributes(courseID: course.id, courseName: course.name, teacher: course.teacher,
            location: course.location, startSection: course.startSection, endSection: course.endSection,
            startDate: occurrence.startDate, endDate: occurrence.endDate, occurrenceID: occurrence.id,
            timeZoneIdentifier: occurrence.timeZoneIdentifier)
    }
}

@Observable
@MainActor
final class LiveActivityController {
    private let client: LiveActivityClient
    private var generation = 0
    private var previewUntil: Date?
    private var previewActivityID: String?
    private var activeTimetableID: UUID?
    private(set) var status = LiveActivityStatus(phase: .idle, message: "打开 App 后会显示当天 6 小时内的当前或下一门课。")

    init(client: LiveActivityClient) { self.client = client }

    func refresh(courses: [Course], enabled: Bool, at now: Date = .now, calendar: Calendar = .current) async {
        await refresh(plan: LiveActivityPlan.make(courses: courses, at: now, calendar: calendar),
            hasCourses: !courses.isEmpty, enabled: enabled, at: now, calendar: calendar, timetableID: nil)
    }

    func refresh(timetable: Timetable, enabled: Bool, at now: Date = .now) async {
        await refresh(plan: LiveActivityPlan.make(timetable: timetable, at: now),
            hasCourses: !timetable.courses.isEmpty, enabled: enabled, at: now,
            calendar: timetable.calendar, timetableID: timetable.id)
    }

    private func refresh(plan: LiveActivityPlan, hasCourses: Bool, enabled: Bool, at now: Date,
                         calendar: Calendar, timetableID: UUID?) async {
        let changedTimetable = activeTimetableID != timetableID
        if changedTimetable {
            activeTimetableID = timetableID
            previewUntil = nil
            previewActivityID = nil
        }
        if let previewUntil, now < previewUntil {
            // Reserve the preview before the first suspension. A periodic refresh
            // must not cancel a preview while old activities are being ended.
            guard let previewActivityID else { return }
            if let handle = client.activities().first(where: { $0.id == previewActivityID }), Self.isVisible(handle.state) {
                status = Self.activeStatus(handle, preview: true)
            } else {
                status = LiveActivityStatus(phase: .failed, message: "预览活动已被系统或手动移除，可再次点击预览。")
            }
            return
        }
        previewUntil = nil
        previewActivityID = nil
        generation += 1
        let revision = generation
        if changedTimetable {
            await clearActivities()
            guard revision == generation else { return }
        }
        guard enabled else {
            await clearActivities()
            guard revision == generation else { return }
            status = LiveActivityStatus(phase: .disabled, message: "自动实时活动已关闭。")
            return
        }
        guard client.authorized() else {
            await clearActivities()
            guard revision == generation else { return }
            status = LiveActivityStatus(phase: .systemDenied, message: "系统未允许实时活动，请在系统设置中为“课表”开启。")
            return
        }
        guard let occurrence = plan.occurrenceToDisplay else {
            if let next = plan.nextOccurrence, let schedule = client.schedule {
                let start = LiveActivityPlan.scheduledStart(for: next, calendar: calendar)
                if start > now {
                    if let existing = client.activities().first(where: {
                        Self.isScheduled($0.state) && LiveActivityCoordinator.matches($0.attributes, occurrence: next)
                    }) {
                        status = Self.scheduledStatus(existing, start: start, calendar: calendar)
                        return
                    }
                    await clearActivities()
                    guard revision == generation else { return }
                    do {
                        let handle = try schedule(next, start)
                        guard Self.isScheduled(handle.state) else {
                            throw LiveActivityError.notActive(String(describing: handle.state))
                        }
                        status = Self.scheduledStatus(handle, start: start, calendar: calendar)
                    } catch {
                        status = LiveActivityStatus(phase: .failed, message: "实时活动计划启动失败：\(error.localizedDescription)。当天课前 6 小时内打开 App 可立即显示。")
                    }
                    return
                }
            }
            await clearActivities()
            guard revision == generation else { return }
            if let next = plan.nextOccurrence {
                let start = Self.startDescription(next.startDate, calendar: calendar)
                status = LiveActivityStatus(phase: .waiting, message: "下一门课：\(next.course.name)，\(start)。当天课前 6 小时内打开 App 后会显示。")
            } else {
                status = LiveActivityStatus(phase: .idle, message: !hasCourses ? "还没有课程，导入课表后即可显示实时活动。" : "课程已结束，目前没有即将开始的课程。")
            }
            return
        }
        if let existing = client.activities().first(where: {
            Self.isVisible($0.state) && LiveActivityCoordinator.matches($0.attributes, occurrence: occurrence)
        }) {
            status = Self.activeStatus(existing, preview: false)
            return
        }
        status = LiveActivityStatus(phase: .starting, message: "正在启动课程实时活动…")
        await clearActivities()
        guard revision == generation else { return }
        do {
            let handle = try client.request(occurrence)
            guard handle.state == .active else {
                throw LiveActivityError.notActive(String(describing: handle.state))
            }
            status = Self.activeStatus(handle, preview: false)
        } catch {
            status = LiveActivityStatus(phase: .failed, message: "实时活动启动失败：\(error.localizedDescription)")
        }
    }

    func preview(course: Course, at now: Date = .now) async throws {
        let start = now.addingTimeInterval(5 * 60)
        let occurrence = CourseOccurrence(course: course, startDate: start, endDate: start.addingTimeInterval(50 * 60))
        try await startPreview(occurrence: occurrence, timetableID: nil)
    }

    func preview(timetable: Timetable, at now: Date = .now) async throws {
        let next = ScheduleEngine.currentOrUpcomingOccurrence(in: timetable, at: now)
        guard let course = next?.course ?? timetable.courses.first else { throw LiveActivityError.noCourses }
        let start = now.addingTimeInterval(5 * 60)
        let occurrence = CourseOccurrence(course: course, startDate: start, endDate: start.addingTimeInterval(50 * 60),
            timetableID: timetable.id, slotID: next?.slotID,
            source: next?.source ?? .weekly(ScheduleEngine.localDateKey(start, calendar: timetable.calendar)),
            timeZoneIdentifier: timetable.timeZoneIdentifier)
        try await startPreview(occurrence: occurrence, timetableID: timetable.id)
    }

    private func startPreview(occurrence: CourseOccurrence, timetableID: UUID?) async throws {
        generation += 1
        let revision = generation
        activeTimetableID = timetableID
        guard client.authorized() else {
            status = LiveActivityStatus(phase: .systemDenied, message: LiveActivityError.disabled.localizedDescription)
            throw LiveActivityError.disabled
        }
        previewUntil = occurrence.endDate
        previewActivityID = nil
        status = LiveActivityStatus(phase: .starting, message: "正在创建灵动岛预览…")
        await clearActivities()
        guard revision == generation else { throw LiveActivityError.superseded }
        do {
            let handle = try client.request(occurrence)
            guard handle.state == .active else {
                throw LiveActivityError.notActive(String(describing: handle.state))
            }
            previewActivityID = handle.id
            status = Self.activeStatus(handle, preview: true)
        } catch {
            previewUntil = nil
            previewActivityID = nil
            status = LiveActivityStatus(phase: .failed, message: "实时活动启动失败：\(error.localizedDescription)")
            throw error
        }
    }

    func endAll() async {
        generation += 1
        let revision = generation
        previewUntil = nil
        previewActivityID = nil
        await clearActivities()
        guard revision == generation else { return }
        status = LiveActivityStatus(phase: .idle, message: "实时活动已结束。")
    }

    static func isVisible(_ state: ActivityState) -> Bool {
        state == .active || state == .stale
    }

    static func isScheduled(_ state: ActivityState) -> Bool {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) { return state == .pending }
#endif
        return false
    }

    private func clearActivities() async {
        // A refresh that suspends cannot end an activity created by a newer
        // operation: only these captured IDs are eligible for cleanup.
        let snapshot = client.activities()
        for handle in snapshot { await client.end(handle) }
    }

    private static func scheduledStatus(_ handle: LiveActivityHandle, start: Date, calendar: Calendar) -> LiveActivityStatus {
        LiveActivityStatus(phase: .scheduled,
            message: "已计划灵动岛：\(handle.attributes.courseName)，将于 \(startDescription(start, calendar: calendar)) 自动开始。",
            activityID: handle.id, activityState: String(describing: handle.state))
    }

    private static func startDescription(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func activeStatus(_ handle: LiveActivityHandle, preview: Bool) -> LiveActivityStatus {
        LiveActivityStatus(phase: preview ? .preview : .active,
            message: "\(preview ? "预览" : "课程")实时活动已激活：\(handle.attributes.courseName)。返回主屏查看倒计时，长按灵动岛查看教室。",
            activityID: handle.id, activityState: String(describing: handle.state))
    }
}

@MainActor
enum LiveActivityCoordinator {
    private static let controller = LiveActivityController(client: .system)
    static var status: LiveActivityStatus { controller.status }

    static func refresh(courses: [Course], at now: Date = .now) async {
        await controller.refresh(courses: courses, enabled: LiveActivityPreferences.isEnabled(), at: now)
    }

    static func refresh(timetable: Timetable, at now: Date = .now) async {
        await controller.refresh(timetable: timetable, enabled: LiveActivityPreferences.isEnabled(), at: now)
    }

    static func preview(course: Course) async throws { try await controller.preview(course: course) }
    static func preview(timetable: Timetable) async throws { try await controller.preview(timetable: timetable) }
    static func endAll() async { await controller.endAll() }

    static func matches(_ attributes: ClassActivityAttributes, occurrence: CourseOccurrence) -> Bool {
        let course = occurrence.course
        let identityMatches = attributes.occurrenceID.map { $0 == occurrence.id }
            ?? (occurrence.timetableID == ScheduleEngine.legacyTimetableID)
        let timeZoneMatches = attributes.timeZoneIdentifier == occurrence.timeZoneIdentifier
            || (attributes.timeZoneIdentifier == nil && occurrence.timetableID == ScheduleEngine.legacyTimetableID)
        return identityMatches && timeZoneMatches
            && attributes.courseID == course.id && attributes.startDate == occurrence.startDate
            && attributes.endDate == occurrence.endDate && attributes.courseName == course.name
            && attributes.teacher == course.teacher && attributes.location == course.location
            && attributes.startSection == course.startSection && attributes.endSection == course.endSection
    }
}

enum LiveActivityError: LocalizedError {
    case disabled, superseded, noCourses, notActive(String)

    var errorDescription: String? {
        switch self {
        case .disabled: "请先在系统设置中允许“实时活动”。"
        case .superseded: "预览被新的操作中断，请再次点击预览。"
        case .noCourses: "当前课表还没有课程，请先添加或导入课程。"
        case .notActive(let state): "系统返回的活动未激活（\(state)），请检查系统实时活动权限并重试。"
        }
    }
}
