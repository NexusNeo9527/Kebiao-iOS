import Foundation

struct CourseOccurrence: Equatable {
    let course: Course
    let startDate: Date
    let endDate: Date
}

enum ScheduleEngine {
    static func date(for day: Weekday, inWeekContaining date: Date, calendar: Calendar = .current) -> Date {
        day.date(inWeekContaining: date, calendar: calendar)
    }

    static func nextOccurrence(for course: Course, after date: Date, calendar: Calendar = .current) -> CourseOccurrence? {
        course.weekdays.compactMap { day -> CourseOccurrence? in
            var start = day.date(inWeekContaining: date, calendar: calendar)
            start = calendar.date(byAdding: .minute, value: course.resolvedStartTimeMinutes, to: start) ?? start
            let duration = max(45, course.sectionCount * 45 + max(0, course.sectionCount - 1) * 10)
            var end = calendar.date(byAdding: .minute, value: duration, to: start) ?? start.addingTimeInterval(Double(duration * 60))

            if end <= date {
                start = calendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 86_400)
                end = calendar.date(byAdding: .minute, value: duration, to: start) ?? start.addingTimeInterval(Double(duration * 60))
            }
            return CourseOccurrence(course: course, startDate: start, endDate: end)
        }.min { $0.startDate < $1.startDate }
    }

    static func currentOrUpcomingOccurrence(in courses: [Course], at date: Date, calendar: Calendar = .current) -> CourseOccurrence? {
        courses.compactMap { nextOccurrence(for: $0, after: date, calendar: calendar) }
            .min { $0.startDate < $1.startDate }
    }
}
