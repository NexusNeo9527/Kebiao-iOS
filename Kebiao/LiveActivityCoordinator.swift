import ActivityKit
import Foundation

enum LiveActivityCoordinator {
    static func refresh(courses: [Course], at now: Date = .now) async {
        guard UserDefaults.standard.bool(forKey: ReminderPreferences.enabledKey),
              ActivityAuthorizationInfo().areActivitiesEnabled,
              let occurrence = ScheduleEngine.currentOrUpcomingOccurrence(in: courses, at: now),
              let leadTime = occurrence.course.reminderMinutesBefore,
              now >= occurrence.startDate.addingTimeInterval(Double(-leadTime * 60)),
              now < occurrence.endDate else {
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
}

enum LiveActivityError: LocalizedError {
    case disabled

    var errorDescription: String? {
        "请先在系统设置中允许“实时活动”。"
    }
}
