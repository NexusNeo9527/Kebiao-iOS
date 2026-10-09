import ActivityKit
import Foundation

@MainActor
enum LiveActivityCoordinator {
    private static var generation = 0
    private static var previewUntil: Date?
    static func refresh(courses: [Course], at now: Date = .now) async {
        if let previewUntil, now < previewUntil { return }
        generation += 1
        let revision = generation
        guard UserDefaults.standard.bool(forKey: ReminderPreferences.enabledKey),
              ActivityAuthorizationInfo().areActivitiesEnabled,
              let occurrence = ScheduleEngine.currentOrUpcomingOccurrence(in: courses.filter { $0.reminderMinutesBefore != nil }, at: now),
              let leadTime = occurrence.course.reminderMinutesBefore else {
            await endAll(invalidate: false)
            return
        }

        let activityStart = occurrence.startDate.addingTimeInterval(Double(-leadTime * 60))
        if now < activityStart {
#if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                await schedule(occurrence, at: activityStart, revision: revision)
                return
            }
#endif
            await endAll(invalidate: false)
            return
        }

        guard now < occurrence.endDate else {
            await endAll(invalidate: false)
            return
        }

        if Activity<ClassActivityAttributes>.activities.contains(where: {
            matches($0.attributes, occurrence: occurrence)
        }) {
            return
        }

        await endAll(invalidate: false)
        guard revision == generation else { return }
        start(occurrence)
    }

    static func preview(course: Course) async throws {
        generation += 1
        let revision = generation
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw LiveActivityError.disabled
        }
        await endAll(invalidate: false)
        guard revision == generation else { return }
        let start = Date.now.addingTimeInterval(5 * 60)
        let end = start.addingTimeInterval(50 * 60)
        try startActivity(course: course, startDate: start, endDate: end)
        previewUntil = end
    }

    static func endAll(invalidate: Bool = true) async {
        if invalidate { generation += 1 }
        previewUntil = nil
        for activity in Activity<ClassActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private static func start(_ occurrence: CourseOccurrence) {
        try? startActivity(
            course: occurrence.course,
            startDate: occurrence.startDate,
            endDate: occurrence.endDate
        )
    }

    @discardableResult
    private static func startActivity(
        course: Course,
        startDate: Date,
        endDate: Date
    ) throws -> Activity<ClassActivityAttributes> {
        let attributes = ClassActivityAttributes(
            courseID: course.id,
            courseName: course.name,
            teacher: course.teacher,
            location: course.location,
            startSection: course.startSection,
            endSection: course.endSection,
            startDate: startDate,
            endDate: endDate
        )
        let content = ActivityContent(
            state: ClassActivityAttributes.ContentState(updatedAt: .now),
            staleDate: endDate
        )
        return try Activity.request(attributes: attributes, content: content, pushType: nil)
    }

#if compiler(>=6.2)
    @available(iOS 26.0, *)
    private static func schedule(_ occurrence: CourseOccurrence, at activityStart: Date, revision: Int) async {
        if Activity<ClassActivityAttributes>.activities.contains(where: {
            matches($0.attributes, occurrence: occurrence)
        }) {
            return
        }

        await endAll(invalidate: false)
        guard revision == generation else { return }
        let course = occurrence.course
        let attributes = ClassActivityAttributes(
            courseID: course.id,
            courseName: course.name,
            teacher: course.teacher,
            location: course.location,
            startSection: course.startSection,
            endSection: course.endSection,
            startDate: occurrence.startDate,
            endDate: occurrence.endDate
        )
        let content = ActivityContent(
            state: ClassActivityAttributes.ContentState(updatedAt: .now),
            staleDate: occurrence.endDate
        )
        let alert = AlertConfiguration(
            title: "即将上课",
            body: "课前提醒已开始，请查看课程安排。",
            sound: .default
        )
        _ = try? Activity.request(
            attributes: attributes,
            content: content,
            pushType: nil,
            style: .standard,
            alertConfiguration: alert,
            start: activityStart
        )
    }
#endif

    static func matches(_ attributes: ClassActivityAttributes, occurrence: CourseOccurrence) -> Bool {
        let course = occurrence.course
        return attributes.courseID == course.id && attributes.startDate == occurrence.startDate
            && attributes.endDate == occurrence.endDate && attributes.courseName == course.name
            && attributes.teacher == course.teacher && attributes.location == course.location
            && attributes.startSection == course.startSection && attributes.endSection == course.endSection
    }
}

enum LiveActivityError: LocalizedError {
    case disabled

    var errorDescription: String? {
        "请先在系统设置中允许“实时活动”。"
    }
}
