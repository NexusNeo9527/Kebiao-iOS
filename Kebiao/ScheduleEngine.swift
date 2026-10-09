import Foundation

struct CourseOccurrence: Equatable {
    let course: Course
    let startDate: Date
    let endDate: Date
}

struct CourseReminder: Equatable {
    let occurrence: CourseOccurrence
    let fireDate: Date
}

enum ScheduleEngine {
    static func date(for day: Weekday, inWeekContaining date: Date, calendar: Calendar = .current) -> Date {
        day.date(inWeekContaining: date, calendar: calendar)
    }

    static func semesterStart(for date: Date, calendar: Calendar = .current) -> Date {
        let defaults = UserDefaults(suiteName: KebiaoConfiguration.appGroupIdentifier) ?? .standard
        if let timestamp = defaults.object(forKey: KebiaoConfiguration.semesterStartKey) as? Double {
            return Weekday.monday.date(inWeekContaining: Date(timeIntervalSince1970: timestamp), calendar: calendar)
        }
        let year = calendar.component(.year, from: date)
        let spring = calendar.date(from: DateComponents(year: year, month: 2, day: 15)) ?? date
        let autumn = calendar.date(from: DateComponents(year: year, month: 9, day: 1)) ?? date
        let reference: Date
        if date >= autumn { reference = autumn }
        else if date >= spring { reference = spring }
        else { reference = calendar.date(from: DateComponents(year: year - 1, month: 9, day: 1)) ?? date }
        return Weekday.monday.date(inWeekContaining: reference, calendar: calendar)
    }

    static func academicWeekNumber(for date: Date, calendar: Calendar = .current, semesterStart: Date? = nil) -> Int {
        let start = Weekday.monday.date(inWeekContaining: semesterStart ?? Self.semesterStart(for: date, calendar: calendar), calendar: calendar)
        let target = Weekday.monday.date(inWeekContaining: date, calendar: calendar)
        let days = calendar.dateComponents([.day], from: start, to: target).day ?? 0
        return Int(floor(Double(days) / 7)) + 1
    }

    static func occurrences(for course: Course, on date: Date, calendar: Calendar = .current, semesterStart: Date? = nil) -> [CourseOccurrence] {
        let starts: [Date]
        if let dates = course.scheduledDates {
            starts = dates.filter { calendar.isDate($0, inSameDayAs: date) }.sorted()
        } else {
            let day = Weekday.from(calendarWeekday: calendar.component(.weekday, from: date))
            guard course.weekdays.contains(day), course.isActive(academicWeek: academicWeekNumber(for: date, calendar: calendar, semesterStart: semesterStart)) else { return [] }
            let start = calendar.date(byAdding: .minute, value: course.resolvedStartTimeMinutes, to: calendar.startOfDay(for: date)) ?? date
            starts = [start]
        }
        return starts.map { start in
            CourseOccurrence(course: course, startDate: start,
                             endDate: calendar.date(byAdding: .minute, value: course.resolvedDurationMinutes, to: start) ?? start)
        }
    }

    static func courses(in courses: [Course], on date: Date, calendar: Calendar = .current) -> [Course] {
        courses.compactMap { course -> (Course, Date)? in
            guard let occurrence = occurrences(for: course, on: date, calendar: calendar).first else { return nil }
            return (course, occurrence.startDate)
        }.sorted { $0.1 == $1.1 ? $0.0.id.uuidString < $1.0.id.uuidString : $0.1 < $1.1 }.map { $0.0 }
    }

    static func nextOccurrence(for course: Course, after date: Date, calendar: Calendar = .current) -> CourseOccurrence? {
        if let dates = course.scheduledDates {
            return dates.sorted().compactMap { start in
                let end = calendar.date(byAdding: .minute, value: course.resolvedDurationMinutes, to: start) ?? start
                return end > date ? CourseOccurrence(course: course, startDate: start, endDate: end) : nil
            }.first
        }
        let today = calendar.startOfDay(for: date)
        let semester = semesterStart(for: date, calendar: calendar)
        for offset in -1...210 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            if let occurrence = occurrences(for: course, on: day, calendar: calendar, semesterStart: semester).first(where: { $0.endDate > date }) { return occurrence }
        }
        return nil
    }

    static func currentOrUpcomingOccurrence(in courses: [Course], at date: Date, calendar: Calendar = .current) -> CourseOccurrence? {
        courses.compactMap { nextOccurrence(for: $0, after: date, calendar: calendar) }.min { $0.startDate < $1.startDate }
    }

    static func reminders(in courses: [Course], after date: Date, calendar: Calendar = .current, limit: Int = 60) -> [CourseReminder] {
        let today = calendar.startOfDay(for: date)
        var reminders: [CourseReminder] = []
        for offset in 0...210 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            for course in courses {
                guard let lead = course.reminderMinutesBefore else { continue }
                for occurrence in occurrences(for: course, on: day, calendar: calendar) {
                    let fire = occurrence.startDate.addingTimeInterval(Double(-lead * 60))
                    if fire > date { reminders.append(CourseReminder(occurrence: occurrence, fireDate: fire)) }
                }
            }
        }
        return Array(reminders.sorted { $0.fireDate < $1.fireDate }.prefix(max(0, limit)))
    }
}
