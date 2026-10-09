import XCTest
@testable import Kebiao

final class TimetableCoreTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.firstWeekday = 2
        return value
    }
    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }
    private func table(_ course: Course) -> Timetable {
        Timetable(semesterStartDate: date(14), timeZoneIdentifier: "GMT", courses: [course])
    }
    private func course(_ slots: [CourseTimeSlot]) -> Course {
        Course(name: "算法", colorValue: 0x5477D9, timeSlots: slots)
    }

    func testLegacyJSONMigratesCourseIdentityWeekdaysAndCrossBreakDuration() throws {
        let identifier = UUID()
        let data = """
        {"id":"\(identifier.uuidString)","name":"旧课程","teacher":"教师","location":"A101",
         "startSection":4,"sectionCount":2,"weekdays":[2,8],"colorValue":5535705,
         "activeWeeks":[1,3,27],"reminderMinutesBefore":null}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Course.self, from: data)
        XCTAssertEqual(decoded.id, identifier)
        XCTAssertEqual(decoded.timeSlots.count, 1)
        XCTAssertEqual(decoded.weekdays, [.monday, .sunday])
        XCTAssertEqual(decoded.activeWeeks, [1, 3, 27])
        XCTAssertNil(decoded.reminderMinutesBefore)
        XCTAssertEqual(decoded.durationMinutes, 100)
        var timetable = table(decoded)
        timetable.normalize()
        XCTAssertEqual(timetable.weekCount, 27)
        try timetable.validate()
        let result = try XCTUnwrap(ScheduleEngine.occurrences(in: timetable, on: date(14)).first)
        XCTAssertEqual(result.endDate.timeIntervalSince(result.startDate), 100 * 60)
    }

    func testCollectionRoundTripPreservesSlotsExceptionsAndDatedEventIDs() throws {
        let event = DatedCourseEvent(startDate: date(15, 18), endDate: date(15, 19))
        let weekly = CourseTimeSlot(teacher: "甲", location: "A101", activeWeeks: [1, 3])
        let dated = CourseTimeSlot(teacher: "乙", location: "B202", datedEvents: [event])
        var value = course([weekly, dated])
        value.exceptions = [CourseException(slotID: dated.id, source: .dated(event.id), action: .replaced,
            startDate: date(16, 10), endDate: date(16, 11), location: "C303")]
        let original = TimetableCollection(timetables: [table(value)])
        try original.validate()
        let restored = try JSONDecoder().decode(TimetableCollection.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.activeTimetable?.courses.first?.timeSlots[1].datedEvents?.first?.id, event.id)
        XCTAssertEqual(ScheduleEngine.occurrences(in: try XCTUnwrap(restored.activeTimetable), on: date(16)).first?.location, "C303")
    }

    func testIndependentSlotsUseTheirOwnDaysLocationsWeeksAndReminderSettings() throws {
        let morning = CourseTimeSlot(teacher: "甲", location: "A101", weekdays: [.monday],
            reminderMinutesBefore: 10, activeWeeks: [1])
        let evening = CourseTimeSlot(teacher: "乙", location: "B202", weekdays: [.monday, .tuesday],
            startTimeMinutes: 18 * 60, reminderMinutesBefore: nil, activeWeeks: [1, 2], durationMinutes: 60)
        let timetable = table(course([morning, evening]))
        let monday = ScheduleEngine.occurrences(in: timetable, on: date(14))
        XCTAssertEqual(monday.map(\.slotID), [morning.id, evening.id])
        XCTAssertEqual(monday.map(\.location), ["A101", "B202"])
        XCTAssertEqual(monday.map(\.startDate), [date(14, 8), date(14, 18)])
        XCTAssertEqual(ScheduleEngine.occurrences(in: timetable, on: date(21)).map(\.slotID), [evening.id])
        XCTAssertEqual(ScheduleEngine.reminders(in: timetable, after: date(14, 7)).count, 1)
    }

    func testSameDayDatedEventsRemainSeparateAndHaveStableIDs() throws {
        let first = DatedCourseEvent(startDate: date(14, 9), endDate: date(14, 10))
        let second = DatedCourseEvent(startDate: date(14, 18), endDate: date(14, 19))
        let slot = CourseTimeSlot(datedEvents: [first, second])
        var value = course([slot])
        let original = ScheduleEngine.occurrences(in: table(value), on: date(14))
        XCTAssertEqual(original.map(\.startDate), [first.startDate, second.startDate])
        XCTAssertEqual(Set(original.map(\.id)).count, 2)
        value.exceptions = [CourseException(slotID: slot.id, source: .dated(first.id), action: .cancelled)]
        let remaining = ScheduleEngine.occurrences(in: table(value), on: date(14))
        XCTAssertEqual(remaining.map(\.source), [.dated(second.id)])
    }

    func testWeeklyIdentityAndCancellationSurviveChangesToSectionTimes() throws {
        let slot = CourseTimeSlot(weekdays: [.monday], activeWeeks: [1, 2])
        var timetable = table(course([slot]))
        let original = try XCTUnwrap(ScheduleEngine.occurrences(in: timetable, on: date(14)).first)
        timetable.courses[0].exceptions = [
            CourseException(slotID: slot.id, source: original.source, action: .cancelled)
        ]
        timetable.sectionPeriods = timetable.sectionPeriods.map {
            SectionPeriod(id: $0.id, startMinutes: $0.startMinutes + 30, endMinutes: $0.endMinutes + 30)
        }
        try timetable.validate()
        XCTAssertTrue(ScheduleEngine.occurrences(in: timetable, on: date(14)).isEmpty)
        let next = try XCTUnwrap(ScheduleEngine.occurrences(in: timetable, on: date(21)).first)
        XCTAssertEqual(next.startDate, date(21, 8, 30))
        var restored = timetable
        restored.courses[0].exceptions = []
        let changed = try XCTUnwrap(ScheduleEngine.occurrences(in: restored, on: date(14)).first)
        XCTAssertEqual(changed.id, original.id)
    }

    func testCourseMovedAcrossDaysDisappearsAtSourceAndAppearsAtDestinationOnce() throws {
        let slot = CourseTimeSlot(teacher: "甲", location: "A101", activeWeeks: [1])
        var value = course([slot])
        value.exceptions = [CourseException(slotID: slot.id, source: .weekly("2026-09-14"), action: .replaced,
            startDate: date(16, 10), endDate: date(16, 11, 30), teacher: "乙", location: "B202")]
        let timetable = table(value)
        try timetable.validate()
        XCTAssertTrue(ScheduleEngine.occurrences(in: timetable, on: date(14)).isEmpty)
        let moved = try XCTUnwrap(ScheduleEngine.occurrences(in: timetable, on: date(16)).first)
        XCTAssertEqual(moved.startDate, date(16, 10))
        XCTAssertEqual(moved.teacher, "乙")
        XCTAssertEqual(moved.location, "B202")
        XCTAssertEqual(moved.source, .weekly("2026-09-14"))
        let week = ScheduleEngine.occurrences(in: timetable, from: date(14), to: date(21))
        XCTAssertEqual(week.count, 1)
        XCTAssertEqual(week.first?.id, moved.id)
        XCTAssertEqual(ScheduleEngine.reminders(in: timetable, after: date(15)).first?.fireDate, date(16, 9, 50))
    }

    func testConfiguredSectionsUseLastSectionEndIncludingLongBreaks() throws {
        let slot = CourseTimeSlot(startSection: 4, sectionCount: 2, activeWeeks: [1])
        let timetable = table(course([slot]))
        let occurrence = try XCTUnwrap(ScheduleEngine.occurrences(in: timetable, on: date(14)).first)
        XCTAssertEqual(occurrence.startDate, date(14, 11, 5))
        XCTAssertEqual(occurrence.endDate, date(14, 14, 45))
        XCTAssertEqual(occurrence.course.resolvedDurationMinutes, 220)
    }

    func testCurrentOccurrenceIncludesOvernightDatedEventAndReminderCanFirePreviousDay() throws {
        let overnight = DatedCourseEvent(startDate: date(14, 23), endDate: date(15, 1))
        let early = DatedCourseEvent(startDate: date(16, 0, 5), endDate: date(16, 1))
        let timetable = table(course([CourseTimeSlot(reminderMinutesBefore: 10, datedEvents: [overnight, early])]))
        XCTAssertEqual(ScheduleEngine.currentOrUpcomingOccurrence(in: timetable, at: date(15, 0, 30))?.source, .dated(overnight.id))
        XCTAssertEqual(ScheduleEngine.reminders(in: timetable, after: date(15, 23)).first?.fireDate, date(15, 23, 55))
    }

    func testOverlappingDayKeepsDatedEventsAndStableIDsUsingTimetableTimeZone() throws {
        // The queried day is September 15 in Shanghai, although the UTC date is September 14.
        let fullDay = DatedCourseEvent(startDate: date(14, 0, 1), endDate: date(15, 0, 1))
        let overnight = DatedCourseEvent(startDate: date(14, 15), endDate: date(14, 17))
        let endsAtMidnight = DatedCourseEvent(startDate: date(14, 14), endDate: date(14, 16))
        let first = DatedCourseEvent(startDate: date(15, 1), endDate: date(15, 2))
        let second = DatedCourseEvent(startDate: date(15, 10), endDate: date(15, 11))
        let nextDay = DatedCourseEvent(startDate: date(15, 16), endDate: date(15, 17))
        let slot = CourseTimeSlot(datedEvents: [fullDay, overnight, endsAtMidnight, first, second, nextDay])
        let timetable = Timetable(semesterStartDate: date(13, 16), timeZoneIdentifier: "Asia/Shanghai",
                                  courses: [course([slot])])
        try timetable.validate()
        let query = date(14, 20)
        let overlapping = ScheduleEngine.occurrencesOverlappingDay(in: timetable, on: query)
        XCTAssertEqual(overlapping.map(\.source), [.dated(fullDay.id), .dated(overnight.id), .dated(first.id), .dated(second.id)])
        XCTAssertEqual(Set(overlapping.map(\.id)).count, 4)
        let previousDay = ScheduleEngine.occurrences(in: timetable, on: date(14, 7))
        for event in [fullDay, overnight] {
            XCTAssertEqual(overlapping.first { $0.source == .dated(event.id) }?.id,
                           previousDay.first { $0.source == .dated(event.id) }?.id)
        }
        // Date-range exports and ordinary day queries continue to select starts on that day.
        XCTAssertEqual(ScheduleEngine.occurrences(in: timetable, on: query).map(\.source), [.dated(first.id), .dated(second.id)])
    }

    func testOverlappingDayIncludesOvernightWeeklyAndMovedCoursesOnce() throws {
        let weekly = CourseTimeSlot(weekdays: [.monday], startTimeMinutes: 23 * 60,
                                    activeWeeks: [1], durationMinutes: 120)
        let movedSlot = CourseTimeSlot(weekdays: [.monday], activeWeeks: [1])
        var value = course([weekly, movedSlot])
        value.exceptions = [CourseException(slotID: movedSlot.id, source: .weekly("2026-09-14"), action: .replaced,
            startDate: date(16, 23), endDate: date(17, 1), location: "补课教室")]
        let timetable = table(value)
        try timetable.validate()
        let monday = try XCTUnwrap(ScheduleEngine.occurrences(in: timetable, on: date(14)).first)
        let tuesday = ScheduleEngine.occurrencesOverlappingDay(in: timetable, on: date(15, 0, 30))
        XCTAssertEqual(tuesday.count, 1)
        XCTAssertEqual(tuesday.first?.id, monday.id)
        XCTAssertEqual(tuesday.first?.endDate, date(15, 1))
        XCTAssertTrue(ScheduleEngine.occurrences(in: timetable, on: date(15)).isEmpty)
        let wednesday = try XCTUnwrap(ScheduleEngine.occurrences(in: timetable, on: date(16)).first)
        let thursday = ScheduleEngine.occurrencesOverlappingDay(in: timetable, on: date(17, 0, 30))
        XCTAssertEqual(thursday.count, 1)
        XCTAssertEqual(thursday.first?.id, wednesday.id)
        XCTAssertEqual(thursday.first?.source, .weekly("2026-09-14"))
        XCTAssertEqual(thursday.first?.location, "补课教室")
        XCTAssertTrue(ScheduleEngine.occurrences(in: timetable, on: date(17)).isEmpty)
    }

    func testValidationRejectsBrokenReferencesUnsupportedVersionAndInvalidPeriods() {
        let slot = CourseTimeSlot()
        var value = course([slot])
        value.exceptions = [CourseException(slotID: UUID(), source: .weekly("2026-09-14"), action: .cancelled)]
        XCTAssertThrowsError(try table(value).validate())
        var timetable = table(course([slot]))
        timetable.sectionPeriods[1].startMinutes = 500
        XCTAssertThrowsError(try timetable.validate())
        let unsupported = TimetableCollection(version: 3, timetables: [table(course([slot]))])
        XCTAssertThrowsError(try unsupported.validate())
        let missing = TimetableCollection(timetables: [table(course([slot]))], activeTimetableID: UUID())
        XCTAssertThrowsError(try missing.validate())
        XCTAssertThrowsError(try CourseTimeSlot(sectionCount: Int.max).validate())
        value.exceptions = [CourseException(slotID: slot.id, source: .weekly("2026-99-99"), action: .cancelled)]
        XCTAssertThrowsError(try value.validate())
    }

    func testOccurrencesUseTimetableTimeZoneInsteadOfDeviceDayBoundaries() throws {
        let slot = CourseTimeSlot(sectionCount: 1, activeWeeks: [1])
        let timetable = Timetable(semesterStartDate: date(13, 16), timeZoneIdentifier: "Asia/Shanghai",
                                  courses: [course([slot])])
        let occurrence = try XCTUnwrap(ScheduleEngine.occurrences(in: timetable, on: date(13, 20)).first)
        XCTAssertEqual(occurrence.startDate, date(14))
        XCTAssertEqual(occurrence.endDate, date(14, 0, 45))
        XCTAssertEqual(occurrence.source, .weekly("2026-09-14"))
        XCTAssertEqual(occurrence.timeZoneIdentifier, "Asia/Shanghai")
    }

    func testLegacyArrayEntryPointsKeepExactDatesAndAllSameDayEvents() {
        var value = Course(name: "旧日期课", teacher: "", location: "", startSection: 1, sectionCount: 2,
            weekdays: [.monday], colorValue: 0x5477D9, startTimeMinutes: nil, reminderMinutesBefore: 10)
        value.scheduledDates = [date(14, 8), date(14, 18)]
        value.durationMinutes = 60
        let occurrences = ScheduleEngine.occurrences(for: value, on: date(14), calendar: calendar)
        XCTAssertEqual(occurrences.count, 2)
        XCTAssertEqual(occurrences.map(\.endDate), [date(14, 9), date(14, 19)])
        XCTAssertTrue(ScheduleEngine.occurrences(for: value, on: date(21), calendar: calendar).isEmpty)
        XCTAssertEqual(ScheduleEngine.reminders(in: [value], after: date(14, 7), calendar: calendar).map(\.fireDate),
                       [date(14, 7, 50), date(14, 17, 50)])
    }
}
