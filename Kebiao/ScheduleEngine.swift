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
            var attempts = 0
            while !course.isActive(academicWeek: academicWeekNumber(for: start, calendar: calendar)), attempts < 30 {
                start = calendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 86_400)
                end = calendar.date(byAdding: .minute, value: duration, to: start) ?? start.addingTimeInterval(Double(duration * 60))
                attempts += 1
            }
            guard attempts < 30 else { return nil }
            return CourseOccurrence(course: course, startDate: start, endDate: end)
        }.min { $0.startDate < $1.startDate }
    }

    static func currentOrUpcomingOccurrence(in courses: [Course], at date: Date, calendar: Calendar = .current) -> CourseOccurrence? {
        courses.compactMap { nextOccurrence(for: $0, after: date, calendar: calendar) }
            .min { $0.startDate < $1.startDate }
    }

    static func academicWeekNumber(for date: Date, calendar: Calendar = .current) -> Int {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let semesterMonth = month >= 8 ? 9 : 2
        let semesterDay = month >= 8 ? 1 : 15
        let reference = calendar.date(from: DateComponents(year: year, month: semesterMonth, day: semesterDay)) ?? date
        let semesterStart = Weekday.monday.date(inWeekContaining: reference, calendar: calendar)
        let targetWeek = Weekday.monday.date(inWeekContaining: date, calendar: calendar)
        let difference = calendar.dateComponents([.weekOfYear], from: semesterStart, to: targetWeek).weekOfYear ?? 0
        return max(1, difference + 1)
    }
}
