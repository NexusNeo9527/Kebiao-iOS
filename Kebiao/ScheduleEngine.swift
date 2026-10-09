import Foundation

struct CourseOccurrence: Equatable, Identifiable {
    let id: String
    let timetableID: UUID
    let slotID: UUID
    let source: OccurrenceSource
    let timeZoneIdentifier: String?
    let course: Course
    let startDate: Date
    let endDate: Date
    var courseID: UUID { course.id }
    var teacher: String { course.teacher }
    var location: String { course.location }
    var reminderMinutesBefore: Int? { course.reminderMinutesBefore }
    init(course: Course, startDate: Date, endDate: Date, timetableID: UUID = ScheduleEngine.legacyTimetableID,
         slotID: UUID? = nil, source: OccurrenceSource? = nil, timeZoneIdentifier: String? = nil) {
        self.course = course; self.startDate = startDate; self.endDate = endDate; self.timetableID = timetableID
        self.timeZoneIdentifier = timeZoneIdentifier
        self.slotID = slotID ?? course.timeSlots.first?.id ?? course.id
        self.source = source ?? .weekly(ScheduleEngine.localDateKey(startDate, calendar: .current))
        self.id = "\(timetableID.uuidString)-\(self.slotID.uuidString)-\(self.source.stableKey)"
    }
}

struct CourseReminder: Equatable {
    let occurrence: CourseOccurrence
    let fireDate: Date
}

enum ScheduleEngine {
    static let legacyTimetableID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static func date(for day: Weekday, inWeekContaining date: Date, calendar: Calendar = .current) -> Date {
        day.date(inWeekContaining: date, calendar: calendar)
    }
    static func semesterStart(for date: Date, calendar: Calendar = .current) -> Date {
        let defaults = UserDefaults(suiteName: KebiaoConfiguration.appGroupIdentifier) ?? .standard
        if let timestamp = defaults.object(forKey: KebiaoConfiguration.semesterStartKey) as? Double {
            return Weekday.monday.date(inWeekContaining: Date(timeIntervalSince1970: timestamp), calendar: calendar)
        }
        return defaultSemesterStart(for: date, calendar: calendar)
    }
    static func defaultSemesterStart(for date: Date, calendar: Calendar = .current) -> Date {
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
    static func localDateKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
    static func date(fromLocalDateKey key: String, calendar: Calendar) -> Date? {
        guard key.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        let values = key.split(separator: "-").compactMap { Int($0) }
        guard values.count == 3,
              let date = calendar.date(from: DateComponents(year: values[0], month: values[1], day: values[2])),
              localDateKey(date, calendar: calendar) == key else { return nil }
        return date
    }
    static func occurrences(in timetable: Timetable, on date: Date) -> [CourseOccurrence] {
        let start = timetable.calendar.startOfDay(for: date)
        let end = timetable.calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return occurrences(in: timetable, from: start, to: end)
    }

    static func occurrencesOverlappingDay(in timetable: Timetable, on date: Date) -> [CourseOccurrence] {
        let start = timetable.calendar.startOfDay(for: date)
        let end = timetable.calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        // Validated courses can last up to 24 hours, including dated and moved arrangements.
        return occurrences(in: timetable, from: start.addingTimeInterval(-86_400), to: end)
            .filter { $0.endDate > start }
    }

    // The interval includes starts at from and excludes starts at to.
    static func occurrences(in timetable: Timetable, from: Date, to: Date) -> [CourseOccurrence] {
        guard to > from else { return [] }
        let calendar = timetable.calendar
        var result: [CourseOccurrence] = []
        for course in timetable.courses {
            for slot in course.timeSlots {
                if let events = slot.datedEvents {
                    for event in events {
                        let source = OccurrenceSource.dated(event.id)
                        if let occurrence = resolvedOccurrence(course: course, slot: slot, source: source,
                            start: event.startDate, end: event.endDate, timetable: timetable),
                           occurrence.startDate >= from, occurrence.startDate < to {
                            result.append(occurrence)
                        }
                    }
                } else {
                    let semesterStart = Weekday.monday.date(inWeekContaining: timetable.semesterStartDate, calendar: calendar)
                    let semesterEnd = calendar.date(byAdding: .day, value: timetable.weekCount * 7, to: semesterStart) ?? semesterStart
                    let windowStart = max(calendar.startOfDay(for: from), semesterStart)
                    let windowEnd = min(to, semesterEnd)
                    var day = windowStart
                    while day < windowEnd {
                        if let base = weeklyOccurrence(course: course, slot: slot, on: day, timetable: timetable),
                           let occurrence = resolvedOccurrence(course: course, slot: slot, source: base.source,
                            start: base.startDate, end: base.endDate, timetable: timetable),
                           occurrence.startDate >= from, occurrence.startDate < to {
                            result.append(occurrence)
                        }
                        guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
                        day = next
                    }
                    // Include courses moved here from an original day outside this interval.
                    for exception in course.exceptions where exception.slotID == slot.id && exception.action == .replaced {
                        guard case .weekly(let key) = exception.source,
                              let originalDay = date(fromLocalDateKey: key, calendar: calendar),
                              originalDay < windowStart || originalDay >= windowEnd,
                              let base = weeklyOccurrence(course: course, slot: slot, on: originalDay, timetable: timetable),
                              let occurrence = resolvedOccurrence(course: course, slot: slot, source: base.source,
                                start: base.startDate, end: base.endDate, timetable: timetable),
                              occurrence.startDate >= from, occurrence.startDate < to else { continue }
                        result.append(occurrence)
                    }
                }
            }
        }
        return result.sorted { $0.startDate == $1.startDate ? $0.id < $1.id : $0.startDate < $1.startDate }
    }
    static func currentOrUpcomingOccurrence(in timetable: Timetable, at date: Date) -> CourseOccurrence? {
        let end = searchEnd(in: timetable, after: date)
        let start = timetable.calendar.date(byAdding: .day, value: -1, to: timetable.calendar.startOfDay(for: date)) ?? date.addingTimeInterval(-86_400)
        return occurrences(in: timetable, from: start, to: end).first { $0.endDate > date }
    }
    static func reminders(in timetable: Timetable, after date: Date, limit: Int = 60) -> [CourseReminder] {
        let end = searchEnd(in: timetable, after: date)
        return Array(occurrences(in: timetable, from: date, to: end).compactMap { occurrence -> CourseReminder? in
            guard let lead = occurrence.reminderMinutesBefore else { return nil }
            let fire = occurrence.startDate.addingTimeInterval(Double(-lead * 60))
            return fire > date ? CourseReminder(occurrence: occurrence, fireDate: fire) : nil
        }.sorted { $0.fireDate == $1.fireDate ? $0.occurrence.id < $1.occurrence.id : $0.fireDate < $1.fireDate }
            .prefix(max(0, limit)))
    }
    private static func searchEnd(in timetable: Timetable, after date: Date) -> Date {
        let calendar = timetable.calendar
        let semester = Weekday.monday.date(inWeekContaining: timetable.semesterStartDate, calendar: calendar)
        let semesterEnd = calendar.date(byAdding: .day, value: timetable.weekCount * 7, to: semester) ?? date
        let datedEnd = timetable.courses.flatMap(\.timeSlots).flatMap { $0.datedEvents ?? [] }.map(\.endDate).max() ?? date
        let movedEnd = timetable.courses.flatMap(\.exceptions).compactMap(\.endDate).max() ?? date
        return max(max(semesterEnd, datedEnd), max(movedEnd, date)).addingTimeInterval(1)
    }
    private static func weeklyOccurrence(course: Course, slot: CourseTimeSlot, on date: Date,
                                         timetable: Timetable) -> CourseOccurrence? {
        let calendar = timetable.calendar
        let week = academicWeekNumber(for: date, calendar: calendar, semesterStart: timetable.semesterStartDate)
        let weekday = Weekday.from(calendarWeekday: calendar.component(.weekday, from: date))
        guard (1...timetable.weekCount).contains(week), slot.weekdays.contains(weekday), slot.isActive(academicWeek: week),
              let first = timetable.sectionPeriods.first(where: { $0.id == slot.startSection }),
              let last = timetable.sectionPeriods.first(where: { $0.id == slot.endSection }) else { return nil }
        let minutes = slot.startTimeMinutes ?? first.startMinutes
        let duration = slot.durationMinutes ?? max(1, last.endMinutes - first.startMinutes)
        let start = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: date) ?? date
        let end: Date
        if slot.startTimeMinutes == nil, slot.durationMinutes == nil {
            if last.endMinutes == 1440 {
                end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? start
            } else {
                end = calendar.date(bySettingHour: last.endMinutes / 60, minute: last.endMinutes % 60,
                                    second: 0, of: date) ?? start
            }
        } else {
            end = calendar.date(byAdding: .minute, value: duration, to: start) ?? start
        }
        return projectedOccurrence(course: course, slot: slot, source: .weekly(localDateKey(date, calendar: calendar)),
                                   start: start, end: end, timetable: timetable)
    }
    private static func resolvedOccurrence(course: Course, slot: CourseTimeSlot, source: OccurrenceSource,
                                           start: Date, end: Date, timetable: Timetable) -> CourseOccurrence? {
        guard let exception = course.exceptions.last(where: { $0.slotID == slot.id && $0.source == source }) else {
            return projectedOccurrence(course: course, slot: slot, source: source, start: start, end: end, timetable: timetable)
        }
        guard exception.action == .replaced, let newStart = exception.startDate, let newEnd = exception.endDate else { return nil }
        var changed = slot
        if let teacher = exception.teacher { changed.teacher = teacher }
        if let location = exception.location { changed.location = location }
        let minutes = timetable.calendar.component(.hour, from: newStart) * 60 + timetable.calendar.component(.minute, from: newStart)
        if let nearest = timetable.sectionPeriods.min(by: { abs($0.startMinutes - minutes) < abs($1.startMinutes - minutes) }) {
            changed.startSection = nearest.id
            changed.sectionCount = max(1, min(changed.sectionCount, timetable.sectionPeriods.count - nearest.id + 1))
        }
        return projectedOccurrence(course: course, slot: changed, source: source, start: newStart, end: newEnd, timetable: timetable)
    }
    private static func projectedOccurrence(course: Course, slot: CourseTimeSlot, source: OccurrenceSource,
                                            start: Date, end: Date, timetable: Timetable) -> CourseOccurrence {
        var projectedSlot = slot
        projectedSlot.startTimeMinutes = timetable.calendar.component(.hour, from: start) * 60 + timetable.calendar.component(.minute, from: start)
        projectedSlot.durationMinutes = max(1, Int(end.timeIntervalSince(start) / 60))
        if case .dated(let eventID) = source {
            projectedSlot.datedEvents = [DatedCourseEvent(id: eventID, startDate: start, endDate: end)]
        }
        let projected = Course(id: course.id, name: course.name, colorValue: course.colorValue,
            credits: course.credits, notes: course.notes, timeSlots: [projectedSlot])
        return CourseOccurrence(course: projected, startDate: start, endDate: end, timetableID: timetable.id,
                                slotID: slot.id, source: source, timeZoneIdentifier: timetable.timeZoneIdentifier)
    }

    // Compatibility entrypoints retain the global semester behavior for callers being migrated.
    private static func legacyTimetable(courses: [Course], at date: Date, calendar: Calendar,
                                        semesterStart: Date? = nil) -> Timetable {
        let compatible = courses.map { course -> Course in
            var value = course
            for index in value.timeSlots.indices where value.timeSlots[index].durationMinutes == nil && value.timeSlots[index].datedEvents == nil {
                value.timeSlots[index].durationMinutes = CourseTimeSlot.legacyDuration(sectionCount: value.timeSlots[index].sectionCount)
            }
            return value
        }
        return Timetable(id: legacyTimetableID, semesterStartDate: semesterStart ?? Self.semesterStart(for: date, calendar: calendar),
                         weekCount: 30, timeZoneIdentifier: calendar.timeZone.identifier, courses: compatible)
    }
    static func occurrences(for course: Course, on date: Date, calendar: Calendar = .current,
                            semesterStart: Date? = nil) -> [CourseOccurrence] {
        occurrences(in: legacyTimetable(courses: [course], at: date, calendar: calendar, semesterStart: semesterStart), on: date)
    }
    static func courses(in courses: [Course], on date: Date, calendar: Calendar = .current) -> [Course] {
        occurrences(in: legacyTimetable(courses: courses, at: date, calendar: calendar), on: date).map(\.course)
    }
    static func nextOccurrence(for course: Course, after date: Date, calendar: Calendar = .current) -> CourseOccurrence? {
        currentOrUpcomingOccurrence(in: legacyTimetable(courses: [course], at: date, calendar: calendar), at: date)
    }
    static func currentOrUpcomingOccurrence(in courses: [Course], at date: Date, calendar: Calendar = .current) -> CourseOccurrence? {
        currentOrUpcomingOccurrence(in: legacyTimetable(courses: courses, at: date, calendar: calendar), at: date)
    }
    static func reminders(in courses: [Course], after date: Date, calendar: Calendar = .current, limit: Int = 60) -> [CourseReminder] {
        reminders(in: legacyTimetable(courses: courses, at: date, calendar: calendar), after: date, limit: limit)
    }
}
