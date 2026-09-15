import ActivityKit
import Foundation

enum LiveActivityCoordinator {
    static func refresh(courses: [Course], at now: Date = .now) async {
        guard UserDefaults.standard.bool(forKey: ReminderPreferences.enabledKey),
              ActivityAuthorizationInfo().areActivitiesEnabled,
              let occurrence = ScheduleEngine.currentOrUpcomingOccurrence(in: courses, at: now),
              let leadTime = occurrence.course.reminderMinutesBefore else {
            await endAll()
            return
        }

        let activityStart = occurrence.startDate.addingTimeInterval(Double(-leadTime * 60))
        if now < activityStart {
#if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                await schedule(occurrence, at: activityStart)
                return
            }
#endif
            await endAll()
            return
        }

        guard now < occurrence.endDate else {
            await endAll()
            return
        }

        if Activity<ClassActivityAttributes>.activities.contains(where: {
            $0.attributes.courseID == occurrence.course.id && $0.attributes.startDate == occurrence.startDate
        }) {
            return
        }

        await endAll()
        start(occurrence)
    }

    static func preview(course: Course) async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw LiveActivityError.disabled
        }
        await endAll()
        let start = Date.now.addingTimeInterval(5 * 60)
        let end = start.addingTimeInterval(50 * 60)
        startActivity(course: course, startDate: start, endDate: end)
    }

    static func endAll() async {
        for activity in Activity<ClassActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private static func start(_ occurrence: CourseOccurrence) {
        startActivity(course: occurrence.course, startDate: occurrence.startDate, endDate: occurrence.endDate)
    }

    private static func startActivity(course: Course, startDate: Date, endDate: Date) {
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
        _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
    }

#if compiler(>=6.2)
    @available(iOS 26.0, *)
    private static func schedule(_ occurrence: CourseOccurrence, at activityStart: Date) async {
        if Activity<ClassActivityAttributes>.activities.contains(where: {
            $0.attributes.courseID == occurrence.course.id && $0.attributes.startDate == occurrence.startDate
        }) {
            return
        }

        await endAll()
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
}

enum LiveActivityError: LocalizedError {
    case disabled

    var errorDescription: String? {
        "请先在系统设置中允许“实时活动”。"
    }
}
