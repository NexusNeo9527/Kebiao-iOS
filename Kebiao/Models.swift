import SwiftUI

enum Weekday: Int, CaseIterable, Codable, Identifiable, Hashable {
    case monday = 2, tuesday, wednesday, thursday, friday, saturday, sunday
    var id: Int { rawValue }
    var shortName: String {
        switch self {
        case .monday: "周一"
        case .tuesday: "周二"
        case .wednesday: "周三"
        case .thursday: "周四"
        case .friday: "周五"
        case .saturday: "周六"
        case .sunday: "周日"
        }
    }
    var fullName: String { shortName }
    var calendarWeekday: Int { self == .sunday ? 1 : rawValue }
    var weekIndex: Int { self == .sunday ? 6 : rawValue - 2 }
    static func from(calendarWeekday: Int) -> Weekday {
        calendarWeekday == 1 ? .sunday : Weekday(rawValue: calendarWeekday) ?? .monday
    }
    static var today: Weekday { from(calendarWeekday: Calendar.current.component(.weekday, from: .now)) }
    func date(inWeekContaining date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        let current = Weekday.from(calendarWeekday: calendar.component(.weekday, from: start))
        return calendar.date(byAdding: .day, value: weekIndex - current.weekIndex, to: start) ?? start
    }
}

enum TimetableValidationError: LocalizedError, Equatable {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

struct SectionPeriod: Identifiable, Codable, Hashable {
    var id: Int
    var startMinutes: Int
    var endMinutes: Int
    static let defaults: [SectionPeriod] = SectionSchedule.starts.enumerated().map {
        SectionPeriod(id: $0.offset + 1, startMinutes: $0.element, endMinutes: $0.element + 45)
    }
}

struct DatedCourseEvent: Identifiable, Codable, Hashable {
    var id: UUID
    var startDate: Date
    var endDate: Date
    init(id: UUID = UUID(), startDate: Date, endDate: Date) {
        self.id = id; self.startDate = startDate; self.endDate = endDate
    }
}

enum OccurrenceSource: Codable, Hashable {
    case weekly(String)
    case dated(UUID)
    var stableKey: String {
        switch self {
        case .weekly(let day): "weekly-\(day)"
        case .dated(let id): "dated-\(id.uuidString)"
        }
    }
}

struct CourseException: Identifiable, Codable, Hashable {
    enum Action: String, Codable, Hashable { case cancelled, replaced }
    var id: UUID
    var slotID: UUID
    var source: OccurrenceSource
    var action: Action
    var startDate: Date?
    var endDate: Date?
    var teacher: String?
    var location: String?
    init(id: UUID = UUID(), slotID: UUID, source: OccurrenceSource, action: Action,
         startDate: Date? = nil, endDate: Date? = nil, teacher: String? = nil, location: String? = nil) {
        self.id = id; self.slotID = slotID; self.source = source; self.action = action
        self.startDate = startDate; self.endDate = endDate; self.teacher = teacher; self.location = location
    }
}

struct CourseTimeSlot: Identifiable, Codable, Hashable {
    var id: UUID
    var teacher: String
    var location: String
    var startSection: Int
    var sectionCount: Int
    var weekdays: Set<Weekday>
    var startTimeMinutes: Int?
    var reminderMinutesBefore: Int?
    var startWeek: Int?
    var endWeek: Int?
    var activeWeeks: Set<Int>?
    var durationMinutes: Int?
    var datedEvents: [DatedCourseEvent]?

    init(id: UUID = UUID(), teacher: String = "", location: String = "", startSection: Int = 1,
         sectionCount: Int = 2, weekdays: Set<Weekday> = [.monday], startTimeMinutes: Int? = nil,
         reminderMinutesBefore: Int? = 10, startWeek: Int? = nil, endWeek: Int? = nil,
         activeWeeks: Set<Int>? = nil, durationMinutes: Int? = nil, datedEvents: [DatedCourseEvent]? = nil) {
        self.id = id; self.teacher = teacher; self.location = location; self.startSection = startSection
        self.sectionCount = sectionCount; self.weekdays = weekdays; self.startTimeMinutes = startTimeMinutes
        self.reminderMinutesBefore = reminderMinutesBefore; self.startWeek = startWeek; self.endWeek = endWeek
        self.activeWeeks = activeWeeks; self.durationMinutes = durationMinutes; self.datedEvents = datedEvents
    }

    var endSection: Int { min(12, min(12, max(1, startSection)) + min(12, max(1, sectionCount)) - 1) }
    var resolvedStartWeek: Int { startWeek ?? 1 }
    var resolvedEndWeek: Int { max(resolvedStartWeek, endWeek ?? 20) }
    var resolvedStartTimeMinutes: Int { startTimeMinutes ?? SectionSchedule.startMinutes(for: startSection) }
    var resolvedDurationMinutes: Int { durationMinutes ?? Self.legacyDuration(sectionCount: sectionCount) }
    static func legacyDuration(sectionCount: Int) -> Int {
        let count = min(12, max(1, sectionCount))
        return count * 45 + (count - 1) * 10
    }
    func isActive(academicWeek: Int) -> Bool {
        activeWeeks.map { $0.contains(academicWeek) } ?? (resolvedStartWeek...resolvedEndWeek).contains(academicWeek)
    }
    var scheduledDates: Set<Date>? {
        get { datedEvents.map { Set($0.map(\.startDate)) } }
        set {
            guard let dates = newValue else { datedEvents = nil; return }
            let existing = datedEvents ?? []
            datedEvents = dates.sorted().map { start in
                let previous = existing.first { $0.startDate == start }
                return DatedCourseEvent(id: previous?.id ?? UUID(), startDate: start,
                    endDate: start.addingTimeInterval(Double(resolvedDurationMinutes * 60)))
            }
        }
    }
    mutating func normalize() {
        startSection = min(12, max(1, startSection))
        sectionCount = min(13 - startSection, max(1, sectionCount))
        if let value = startTimeMinutes { startTimeMinutes = min(1439, max(0, value)) }
        if let value = reminderMinutesBefore { reminderMinutesBefore = min(120, max(1, value)) }
        if let value = startWeek { startWeek = min(30, max(1, value)) }
        if let value = endWeek { endWeek = min(30, max(resolvedStartWeek, value)) }
        if let values = activeWeeks { activeWeeks = Set(values.filter { (1...30).contains($0) }) }
        if let value = durationMinutes { durationMinutes = min(1440, max(1, value)) }
    }
    func validate() throws {
        guard (1...12).contains(startSection), sectionCount > 0, sectionCount <= 13 - startSection else {
            throw TimetableValidationError.invalid("课程节次必须在第 1–12 节内。")
        }
        guard startTimeMinutes.map({ (0...1439).contains($0) }) ?? true,
              durationMinutes.map({ (1...1440).contains($0) }) ?? true,
              reminderMinutesBefore.map({ (1...120).contains($0) }) ?? true else {
            throw TimetableValidationError.invalid("课程时间或提醒提前量无效。")
        }
        guard startWeek.map({ (1...30).contains($0) }) ?? true,
              endWeek.map({ $0 >= resolvedStartWeek && $0 <= 30 }) ?? true,
              activeWeeks.map({ $0.allSatisfy { (1...30).contains($0) } }) ?? true else {
            throw TimetableValidationError.invalid("课程周次必须在第 1–30 周内。")
        }
        if let events = datedEvents {
            guard Set(events.map(\.id)).count == events.count,
                  events.allSatisfy({ $0.startDate.timeIntervalSince1970.isFinite && $0.endDate.timeIntervalSince1970.isFinite &&
                      $0.endDate > $0.startDate && $0.endDate.timeIntervalSince($0.startDate) <= 86_400 }) else {
                throw TimetableValidationError.invalid("具体日期课程的标识或起止时间无效。")
            }
        } else if weekdays.isEmpty {
            throw TimetableValidationError.invalid("每周课程至少需要一个上课日。")
        }
    }
}

struct Course: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var colorValue: Int
    var credits: Double?
    var notes: String?
    var timeSlots: [CourseTimeSlot]
    var exceptions: [CourseException]

    init(id: UUID = UUID(), name: String, colorValue: Int, credits: Double? = nil, notes: String? = nil,
         timeSlots: [CourseTimeSlot], exceptions: [CourseException] = []) {
        self.id = id; self.name = name; self.colorValue = colorValue; self.credits = credits
        self.notes = notes; self.timeSlots = timeSlots; self.exceptions = exceptions
    }

    // Existing parsers create a single independent slot through this initializer.
    init(id: UUID = UUID(), name: String, teacher: String, location: String, startSection: Int, sectionCount: Int,
         weekdays: Set<Weekday>, colorValue: Int, startTimeMinutes: Int?, reminderMinutesBefore: Int?,
         startWeek: Int? = nil, endWeek: Int? = nil, activeWeeks: Set<Int>? = nil,
         credits: Double? = nil, notes: String? = nil, scheduledDates: Set<Date>? = nil, durationMinutes: Int? = nil) {
        var slot = CourseTimeSlot(teacher: teacher, location: location, startSection: startSection,
            sectionCount: sectionCount, weekdays: weekdays, startTimeMinutes: startTimeMinutes,
            reminderMinutesBefore: reminderMinutesBefore, startWeek: startWeek, endWeek: endWeek,
            activeWeeks: activeWeeks, durationMinutes: durationMinutes)
        slot.scheduledDates = scheduledDates
        self.init(id: id, name: name, colorValue: colorValue, credits: credits, notes: notes, timeSlots: [slot])
    }

    private var firstSlot: CourseTimeSlot { timeSlots.first ?? CourseTimeSlot() }
    private mutating func changeFirstSlot(_ change: (inout CourseTimeSlot) -> Void) {
        if timeSlots.isEmpty { timeSlots.append(CourseTimeSlot()) }
        change(&timeSlots[0])
    }
    var teacher: String { get { firstSlot.teacher } set { changeFirstSlot { $0.teacher = newValue } } }
    var location: String { get { firstSlot.location } set { changeFirstSlot { $0.location = newValue } } }
    var startSection: Int { get { firstSlot.startSection } set { changeFirstSlot { $0.startSection = newValue } } }
    var sectionCount: Int { get { firstSlot.sectionCount } set { changeFirstSlot { $0.sectionCount = newValue } } }
    var weekdays: Set<Weekday> { get { firstSlot.weekdays } set { changeFirstSlot { $0.weekdays = newValue } } }
    var startTimeMinutes: Int? { get { firstSlot.startTimeMinutes } set { changeFirstSlot { $0.startTimeMinutes = newValue } } }
    var reminderMinutesBefore: Int? { get { firstSlot.reminderMinutesBefore } set { changeFirstSlot { $0.reminderMinutesBefore = newValue } } }
    var startWeek: Int? { get { firstSlot.startWeek } set { changeFirstSlot { $0.startWeek = newValue } } }
    var endWeek: Int? { get { firstSlot.endWeek } set { changeFirstSlot { $0.endWeek = newValue } } }
    var activeWeeks: Set<Int>? { get { firstSlot.activeWeeks } set { changeFirstSlot { $0.activeWeeks = newValue } } }
    var scheduledDates: Set<Date>? { get { firstSlot.scheduledDates } set { changeFirstSlot { $0.scheduledDates = newValue } } }
    var durationMinutes: Int? {
        get { firstSlot.durationMinutes }
        set {
            changeFirstSlot { slot in
                slot.durationMinutes = newValue
                if let events = slot.datedEvents {
                    let duration = slot.resolvedDurationMinutes
                    slot.datedEvents = events.map {
                        DatedCourseEvent(id: $0.id, startDate: $0.startDate,
                            endDate: $0.startDate.addingTimeInterval(Double(duration * 60)))
                    }
                }
            }
        }
    }
    var color: Color { Color(hex: colorValue) }
    var resolvedStartTimeMinutes: Int { firstSlot.resolvedStartTimeMinutes }
    var resolvedDurationMinutes: Int { firstSlot.resolvedDurationMinutes }
    var endSection: Int { firstSlot.endSection }
    var resolvedStartWeek: Int { firstSlot.resolvedStartWeek }
    var resolvedEndWeek: Int { firstSlot.resolvedEndWeek }
    func isActive(academicWeek: Int) -> Bool { firstSlot.isActive(academicWeek: academicWeek) }
    mutating func normalize() {
        for index in timeSlots.indices { timeSlots[index].normalize() }
        if let value = credits { credits = min(20, max(0, value)) }
    }
    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !timeSlots.isEmpty,
              Set(timeSlots.map(\.id)).count == timeSlots.count,
              credits.map({ $0.isFinite && (0...20).contains($0) }) ?? true else {
            throw TimetableValidationError.invalid("课程名称、时段或学分无效。")
        }
        try timeSlots.forEach { try $0.validate() }
        guard Set(exceptions.map(\.id)).count == exceptions.count,
              Set(exceptions.map { "\($0.slotID.uuidString)-\($0.source.stableKey)" }).count == exceptions.count else {
            throw TimetableValidationError.invalid("同一次课程只能有一个调停课安排。")
        }
        for exception in exceptions {
            guard let slot = timeSlots.first(where: { $0.id == exception.slotID }) else {
                throw TimetableValidationError.invalid("调停课安排引用了不存在的时段。")
            }
            switch exception.source {
            case .weekly(let day):
                guard slot.datedEvents == nil,
                      ScheduleEngine.date(fromLocalDateKey: day, calendar: Calendar(identifier: .gregorian)) != nil else {
                    throw TimetableValidationError.invalid("调停课的原始日期无效。")
                }
            case .dated(let eventID):
                guard slot.datedEvents?.contains(where: { $0.id == eventID }) == true else {
                    throw TimetableValidationError.invalid("调停课安排引用了不存在的日期课程。")
                }
            }
            if exception.action == .replaced {
                guard let start = exception.startDate, let end = exception.endDate,
                      start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite,
                      end > start, end.timeIntervalSince(start) <= 86_400 else {
                    throw TimetableValidationError.invalid("调课后的起止时间无效。")
                }
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, colorValue, credits, notes, timeSlots, exceptions
        case teacher, location, startSection, sectionCount, weekdays, startTimeMinutes, reminderMinutesBefore
        case startWeek, endWeek, activeWeeks, scheduledDates, durationMinutes
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let name = try values.decode(String.self, forKey: .name)
        let color = try values.decode(Int.self, forKey: .colorValue)
        let credits = try values.decodeIfPresent(Double.self, forKey: .credits)
        let notes = try values.decodeIfPresent(String.self, forKey: .notes)
        if values.contains(.timeSlots) {
            self.init(id: id, name: name, colorValue: color, credits: credits, notes: notes,
                timeSlots: try values.decode([CourseTimeSlot].self, forKey: .timeSlots),
                exceptions: try values.decodeIfPresent([CourseException].self, forKey: .exceptions) ?? [])
        } else {
            self.init(id: id, name: name, teacher: try values.decode(String.self, forKey: .teacher),
                location: try values.decode(String.self, forKey: .location),
                startSection: try values.decode(Int.self, forKey: .startSection),
                sectionCount: try values.decode(Int.self, forKey: .sectionCount),
                weekdays: try values.decode(Set<Weekday>.self, forKey: .weekdays), colorValue: color,
                startTimeMinutes: try values.decodeIfPresent(Int.self, forKey: .startTimeMinutes),
                reminderMinutesBefore: try values.decodeIfPresent(Int.self, forKey: .reminderMinutesBefore),
                startWeek: try values.decodeIfPresent(Int.self, forKey: .startWeek),
                endWeek: try values.decodeIfPresent(Int.self, forKey: .endWeek),
                activeWeeks: try values.decodeIfPresent(Set<Int>.self, forKey: .activeWeeks), credits: credits, notes: notes,
                scheduledDates: try values.decodeIfPresent(Set<Date>.self, forKey: .scheduledDates),
                durationMinutes: try values.decodeIfPresent(Int.self, forKey: .durationMinutes))
            // Only persisted v1 records need the old 45-minute/10-minute duration preserved.
            if durationMinutes == nil, scheduledDates == nil {
                let first = SectionPeriod.defaults.first { $0.id == max(1, min(12, startSection)) }!
                let last = SectionPeriod.defaults.first { $0.id == endSection }!
                let legacy = CourseTimeSlot.legacyDuration(sectionCount: sectionCount)
                if last.endMinutes - first.startMinutes != legacy { durationMinutes = legacy }
            }
        }
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id); try values.encode(name, forKey: .name)
        try values.encode(colorValue, forKey: .colorValue); try values.encodeIfPresent(credits, forKey: .credits)
        try values.encodeIfPresent(notes, forKey: .notes); try values.encode(timeSlots, forKey: .timeSlots)
        try values.encode(exceptions, forKey: .exceptions)
    }

    static let samples: [Course] = [
        Course(name: "高等数学", teacher: "陈老师", location: "教学楼 A201", startSection: 1, sectionCount: 2, weekdays: [.monday, .wednesday], colorValue: 0xE8795A, startTimeMinutes: nil, reminderMinutesBefore: 10),
        Course(name: "大学英语", teacher: "林老师", location: "教学楼 B103", startSection: 3, sectionCount: 2, weekdays: [.tuesday, .thursday], colorValue: 0x5477D9, startTimeMinutes: nil, reminderMinutesBefore: 10),
        Course(name: "数据结构", teacher: "王老师", location: "实验楼 302", startSection: 5, sectionCount: 2, weekdays: [.monday, .friday], colorValue: 0x3F9D80, startTimeMinutes: nil, reminderMinutesBefore: 10),
        Course(name: "体育", teacher: "张老师", location: "操场", startSection: 7, sectionCount: 2, weekdays: [.wednesday], colorValue: 0xD19436, startTimeMinutes: nil, reminderMinutesBefore: 10)
    ]
}

struct Timetable: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var semesterStartDate: Date
    var weekCount: Int
    var timeZoneIdentifier: String
    var sectionPeriods: [SectionPeriod]
    var courses: [Course]
    init(id: UUID = UUID(), name: String = "默认课表", semesterStartDate: Date = ScheduleEngine.defaultSemesterStart(for: .now),
         weekCount: Int = 20, timeZoneIdentifier: String = TimeZone.current.identifier,
         sectionPeriods: [SectionPeriod] = SectionPeriod.defaults, courses: [Course] = []) {
        self.id = id; self.name = name; self.semesterStartDate = semesterStartDate; self.weekCount = weekCount
        self.timeZoneIdentifier = timeZoneIdentifier; self.sectionPeriods = sectionPeriods; self.courses = courses
    }
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        value.firstWeekday = 2; value.minimumDaysInFirstWeek = 4
        return value
    }
    mutating func normalize() {
        weekCount = min(30, max(1, weekCount))
        for index in courses.indices { courses[index].normalize() }
        let lastWeek = courses.flatMap(\.timeSlots).filter { $0.datedEvents == nil }.map {
            $0.activeWeeks.map { $0.max() ?? 0 } ?? $0.resolvedEndWeek
        }.max() ?? weekCount
        weekCount = min(30, max(weekCount, lastWeek))
        sectionPeriods.sort { $0.id < $1.id }
    }
    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, (1...30).contains(weekCount),
              TimeZone(identifier: timeZoneIdentifier) != nil, semesterStartDate.timeIntervalSince1970.isFinite else {
            throw TimetableValidationError.invalid("课表名称、学期周数、日期或时区无效。")
        }
        let periods = sectionPeriods.sorted { $0.id < $1.id }
        guard (1...12).contains(periods.count), periods.map(\.id) == Array(1...periods.count),
              periods.allSatisfy({ (0...1439).contains($0.startMinutes) && (1...1440).contains($0.endMinutes) && $0.endMinutes > $0.startMinutes }),
              zip(periods, periods.dropFirst()).allSatisfy({ $0.0.endMinutes <= $0.1.startMinutes }) else {
            throw TimetableValidationError.invalid("作息必须按节次排列，起止时间有效且互不重叠。")
        }
        guard Set(courses.map(\.id)).count == courses.count,
              Set(courses.flatMap(\.timeSlots).map(\.id)).count == courses.flatMap(\.timeSlots).count else {
            throw TimetableValidationError.invalid("课程或时段标识重复。")
        }
        let events = courses.flatMap(\.timeSlots).flatMap { $0.datedEvents ?? [] }
        guard Set(events.map(\.id)).count == events.count else {
            throw TimetableValidationError.invalid("具体日期课程的标识重复。")
        }
        try courses.forEach { try $0.validate() }
        guard courses.flatMap(\.timeSlots).allSatisfy({ $0.endSection <= periods.count }) else {
            throw TimetableValidationError.invalid("课程节次超出了本课表的作息。")
        }
        guard courses.flatMap(\.timeSlots).filter({ $0.datedEvents == nil }).allSatisfy({
            ($0.activeWeeks.map { $0.max() ?? 0 } ?? $0.resolvedEndWeek) <= weekCount
        }) else {
            throw TimetableValidationError.invalid("课程周次超出了本课表的学期周数。")
        }
    }
}

struct TimetableCollection: Codable, Hashable {
    var version: Int
    var timetables: [Timetable]
    var activeTimetableID: UUID
    init(version: Int = 2, timetables: [Timetable], activeTimetableID: UUID? = nil) {
        self.version = version; self.timetables = timetables
        self.activeTimetableID = activeTimetableID ?? timetables.first?.id ?? UUID()
    }
    var activeTimetable: Timetable? { timetables.first { $0.id == activeTimetableID } }
    mutating func normalize() { for index in timetables.indices { timetables[index].normalize() } }
    func validate() throws {
        guard version == 2, !timetables.isEmpty, Set(timetables.map(\.id)).count == timetables.count,
              activeTimetable != nil else {
            throw TimetableValidationError.invalid("备份版本、课表集合或当前课表无效。")
        }
        try timetables.forEach { try $0.validate() }
    }
}

enum SectionSchedule {
    static let starts = [480, 535, 610, 665, 840, 895, 970, 1025, 1140, 1195, 1250, 1305]
    static func startMinutes(for section: Int) -> Int { starts[min(12, max(1, section)) - 1] }
}

extension Color {
    init(hex: Int) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}
