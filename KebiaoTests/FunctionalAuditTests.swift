import XCTest
@testable import Kebiao

final class FunctionalAuditTests: XCTestCase {
    func testPortalGridUsesCellWeekdayInsteadOfTeacherNameAndPreservesSplitWeeks() throws {
        let payload = """
        __KEBIAO_GRID__[{"weekday":"星期二","section":"5-6","text":"操作系统\\n教师：周一老师\\n地点：A103\\n第5-6节 2-14周(双),15-16周"}]
        """
        let result = try ScheduleImportService.parseSchoolPortalPayload(payload)
        let course = try XCTUnwrap(result.courses.first)
        XCTAssertEqual(course.weekdays, [.tuesday])
        XCTAssertEqual(course.startSection, 5)
        XCTAssertEqual(course.sectionCount, 2)
        XCTAssertEqual(course.teacher, "周一老师")
        XCTAssertEqual(course.location, "A103")
        XCTAssertEqual(course.activeWeeks, Set([2, 4, 6, 8, 10, 12, 14, 15, 16]))
    }

    func testPortalGridSkipsMissingSectionsAndKeepsSeparateCoursesInOneCell() throws {
        let cells = [
            ScheduleImportService.TimetableGridCell(weekday: "星期五", section: "", text: "缺少节次\n1-16周"),
            ScheduleImportService.TimetableGridCell(weekday: "星期五", section: "7-8",
                text: "算法\n1-9周(单)\n\n英语\n10-16周(双)")
        ]
        let result = try ScheduleImportService.parseTimetableGrid(cells, sourceName: "课表", format: .portal)
        XCTAssertEqual(result.courses.map(\.name), ["算法", "英语"])
        XCTAssertEqual(result.courses.map(\.startSection), [7, 7])
        XCTAssertEqual(result.courses[0].activeWeeks, Set([1, 3, 5, 7, 9]))
        XCTAssertEqual(result.courses[1].activeWeeks, Set([10, 12, 14, 16]))
        XCTAssertEqual(result.warnings.count, 1)
    }

    func testPortalEntryRemovesTemporaryCredentialsAndPreservesApplicationRoute() throws {
        let url = try XCTUnwrap(URLComponents(string: "https://ehall.cqut.edu.cn/new_office_hall/#/personalInfo?ticket=test-ticket&state=null"))
        let entry = try XCTUnwrap(ImportScheduleView.stablePortalEntry(from: url))
        XCTAssertEqual(entry.absoluteString, "https://ehall.cqut.edu.cn/new_office_hall/#/personalInfo")
        let query = try XCTUnwrap(URLComponents(string: "https://school.example/app?ticket=test&semester=1"))
        XCTAssertEqual(ImportScheduleView.stablePortalEntry(from: query)?.absoluteString,
                       "https://school.example/app?semester=1")
    }
    func testImportPreviewKeepsCurrentWeekWhenItContainsCourses() {
        var value = course()
        value.activeWeeks = [2, 4]
        let preview = ScheduleImportPreview(sourceName: "课表.pdf", format: .pdf,
                                            courses: [value], warnings: [])
        let reference = date(2026, 9, 16)
        XCTAssertEqual(preview.timetablePreviewDate(reference: reference,
                         semesterStart: date(2026, 9, 7), calendar: calendar), reference)
    }

    func testImportPreviewOpensFirstActiveWeekInsteadOfAnEmptyWeek() {
        var value = course()
        value.activeWeeks = [8, 10]
        let preview = ScheduleImportPreview(sourceName: "课表.pdf", format: .pdf,
                                            courses: [value], warnings: [])
        let selected = preview.timetablePreviewDate(reference: date(2026, 9, 16),
                         semesterStart: date(2026, 9, 7), calendar: calendar)
        XCTAssertEqual(selected, date(2026, 10, 26))
        XCTAssertFalse(ScheduleEngine.occurrences(for: value, on: selected, calendar: calendar,
                         semesterStart: date(2026, 9, 7)).isEmpty)
    }

    func testImportPreviewUsesExactEventDateAndHandlesEmptySchedules() {
        var value = course()
        value.scheduledDates = [date(2027, 1, 13, 10)]
        let preview = ScheduleImportPreview(sourceName: "课表.ics", format: .ics,
                                            courses: [value], warnings: [])
        let reference = date(2026, 9, 16)
        XCTAssertEqual(preview.timetablePreviewDate(reference: reference,
                         semesterStart: date(2026, 9, 7), calendar: calendar), date(2027, 1, 13, 10))
        let empty = ScheduleImportPreview(sourceName: "课表.pdf", format: .pdf, courses: [], warnings: [])
        XCTAssertEqual(empty.timetablePreviewDate(reference: reference,
                         semesterStart: date(2026, 9, 7), calendar: calendar), reference)
    }

    func testFourOverlappingCoursesStayInOneGroupWithoutLosingCourses() {
        let courses = (0..<4).map { _ in course() }
        let groups = TimetableCourseGroup.groups(courses)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].courses.map(\.id)), Set(courses.map(\.id)))
        XCTAssertEqual(groups[0].startSection, 1)
        XCTAssertEqual(groups[0].endSection, 2)
    }

    func testTransitiveOverlapKeepsBoundsAndAdjacentPeriodsSeparate() {
        var first = course()
        first.sectionCount = 3
        var middle = course()
        middle.startSection = 3
        middle.sectionCount = 3
        var last = course()
        last.startSection = 5
        var adjacent = course()
        adjacent.startSection = 7
        let groups = TimetableCourseGroup.groups([adjacent, last, first, middle])
        XCTAssertEqual(groups.map { $0.courses.count }, [3, 1])
        XCTAssertEqual(groups[0].startSection, 1)
        XCTAssertEqual(groups[0].endSection, 6)
        XCTAssertEqual(groups[1].startSection, 7)
        XCTAssertTrue(TimetableCourseGroup.groups([]).isEmpty)
    }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.firstWeekday = 2
        return value
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func course() -> Course {
        Course(name: "网络", teacher: "老师", location: "A101", startSection: 1, sectionCount: 2,
               weekdays: [.monday], colorValue: 0x5477D9, startTimeMinutes: 480, reminderMinutesBefore: 10)
    }

    func testJanuaryContinuesPreviousAutumnAndCustomSemesterSupportsPreStart() {
        XCTAssertEqual(ScheduleEngine.academicWeekNumber(for: date(2027, 1, 4), calendar: calendar,
                                                        semesterStart: date(2026, 9, 1)), 19)
        XCTAssertEqual(ScheduleEngine.academicWeekNumber(for: date(2026, 8, 31), calendar: calendar,
                                                        semesterStart: date(2026, 9, 7)), 0)
        // Explicit reference keeps this assertion independent of user defaults.
        XCTAssertEqual(ScheduleEngine.academicWeekNumber(for: date(2026, 9, 16), calendar: calendar,
                                                        semesterStart: date(2026, 9, 7)), 2)
    }

    func testReminderUsesExactDatesSortsGloballyAndSkipsDisabledOrPastReminders() {
        var a = course()
        a.scheduledDates = [date(2026, 9, 14, 8), date(2026, 9, 28, 8)]
        var b = course()
        b.id = UUID()
        b.scheduledDates = [date(2026, 9, 14, 9)]
        var disabled = b
        disabled.reminderMinutesBefore = nil
        let reminders = ScheduleEngine.reminders(in: [b, a, disabled], after: date(2026, 9, 14, 7), calendar: calendar)
        XCTAssertEqual(reminders.map(\.fireDate), [date(2026, 9, 14, 7, 50), date(2026, 9, 14, 8, 50), date(2026, 9, 28, 7, 50)])
        XCTAssertEqual(ScheduleEngine.reminders(in: [a], after: date(2026, 9, 14, 7, 55), calendar: calendar).count, 1)
        XCTAssertEqual(ScheduleEngine.reminders(in: [b, a], after: date(2026, 9, 14, 7), calendar: calendar, limit: 1).first?.occurrence.course.id, a.id)
    }

    func testReminderCanFireOnPreviousDay() {
        var value = course()
        value.scheduledDates = [date(2026, 9, 15, 0, 5)]
        let result = ScheduleEngine.reminders(in: [value], after: date(2026, 9, 14, 23), calendar: calendar)
        XCTAssertEqual(result.first?.fireDate, date(2026, 9, 14, 23, 55))
    }

    func testDailyCoursesSortByActualStartAndSingleEventDoesNotRepeat() {
        var late = course()
        late.scheduledDates = [date(2026, 9, 14, 18)]
        var early = course()
        early.startSection = 3
        early.scheduledDates = [date(2026, 9, 14, 9)]
        XCTAssertEqual(ScheduleEngine.courses(in: [late, early], on: date(2026, 9, 14), calendar: calendar).map(\.id), [early.id, late.id])
        XCTAssertTrue(ScheduleEngine.courses(in: [early], on: date(2026, 9, 21), calendar: calendar).isEmpty)
        XCTAssertNil(ScheduleEngine.nextOccurrence(for: early, after: date(2026, 9, 15), calendar: calendar))
    }

    func testMergeSignatureDistinguishesWeeksDurationAndClockTime() {
        let original = course()
        var changed = original
        changed.activeWeeks = [2, 4]
        XCTAssertNotEqual(CourseSignature(original), CourseSignature(changed))
        changed = original
        changed.sectionCount = 3
        XCTAssertNotEqual(CourseSignature(original), CourseSignature(changed))
        changed = original
        changed.startTimeMinutes = 600
        XCTAssertNotEqual(CourseSignature(original), CourseSignature(changed))
    }

    func testImportRetainsOddAndDiscontinuousWeeksWithoutInferringFromSections() throws {
        let csv = "课程名称,星期,节次,上课周数\n网络,周一,5-7,\"1-9周(单),14-16周\""
        let imported = try XCTUnwrap(ScheduleImportService.parseCSV(Data(csv.utf8)).0.first)
        XCTAssertEqual(imported.startSection, 5)
        XCTAssertEqual(imported.sectionCount, 3)
        XCTAssertEqual(imported.activeWeeks, [1, 3, 5, 7, 9, 14, 15, 16])
        let noWeeks = try ScheduleImportService.parseSchoolText("课程名称\t上课时间\n网络\t周一第3-4节")
        XCTAssertNil(noWeeks.courses.first?.startWeek)
        XCTAssertNil(noWeeks.courses.first?.activeWeeks)
    }

    func testSinglePeriodRangeAndRepeatedTableHeaders() throws {
        let input = "导航\t链接\n首页\t返回\n\n课程名称\t星期\t节次\n网络\t周一\t7-7\n\n星期\t课程名称\t节次\n周三\t算法\t5-7"
        let result = try ScheduleImportService.parseSchoolText(input)
        XCTAssertEqual(result.courses.count, 2)
        XCTAssertEqual(result.courses[0].sectionCount, 1)
        XCTAssertEqual(result.courses[1].sectionCount, 3)
        XCTAssertEqual(result.courses[1].weekdays, [.wednesday])
    }

    func testNativeJSONRoundTripKeepsSundayAndOptionalFields() throws {
        var original = course()
        original.weekdays = [.sunday]
        original.activeWeeks = [3, 5]
        original.startWeek = 3
        original.endWeek = 5
        original.reminderMinutesBefore = nil
        original.scheduledDates = [date(2026, 9, 20, 8)]
        original.durationMinutes = 70
        let decoded = try ScheduleImportService.parseJSON(JSONEncoder().encode([original])).0
        XCTAssertEqual(decoded, [original])
    }

    func testICSSingleEventHasOneAbsoluteStart() throws {
        let data = Data("BEGIN:VCALENDAR\nBEGIN:VEVENT\nSUMMARY:网络\nDTSTART:20260914T080000Z\nDTEND:20260914T090000Z\nEND:VEVENT\nEND:VCALENDAR".utf8)
        let value = try XCTUnwrap(ScheduleImportService.parseICS(data).0.first)
        XCTAssertEqual(value.scheduledDates, [date(2026, 9, 14, 8)])
        XCTAssertEqual(value.durationMinutes, 60)
    }

    func testICSIntervalCountAndExclusionAreRetained() throws {
        let data = Data("BEGIN:VEVENT\nSUMMARY:网络\nDTSTART:20260914T080000Z\nDTEND:20260914T090000Z\nRRULE:FREQ=WEEKLY;INTERVAL=2;COUNT=3\nEXDATE:20260928T080000Z\nEND:VEVENT".utf8)
        let values = try ScheduleImportService.parseICS(data).0
        let starts = Set(values.flatMap { Array($0.scheduledDates ?? []) })
        XCTAssertEqual(starts, [date(2026, 9, 14, 8), date(2026, 10, 12, 8)])
    }

    func testICSUntilAndNewYorkTimeZone() throws {
        let data = Data("BEGIN:VEVENT\nSUMMARY:网络\nDTSTART;TZID=America/New_York:20260914T080000\nDTEND;TZID=America/New_York:20260914T090000\nRRULE:FREQ=WEEKLY;UNTIL=20260921T120000Z\nEND:VEVENT".utf8)
        let values = try ScheduleImportService.parseICS(data).0
        XCTAssertEqual(Set(values.flatMap { Array($0.scheduledDates ?? []) }), [date(2026, 9, 14, 12), date(2026, 9, 21, 12)])
    }

    func testICSUnsupportedRecurrenceDoesNotInventCourses() throws {
        let data = Data("BEGIN:VEVENT\nSUMMARY:网络\nDTSTART:20260914T080000Z\nRRULE:FREQ=MONTHLY;BYDAY=1MO\nEND:VEVENT".utf8)
        let result = try ScheduleImportService.parseICS(data)
        XCTAssertTrue(result.0.isEmpty)
        XCTAssertFalse(result.1.isEmpty)
    }

    @MainActor
    func testLiveActivityMatchesAllDisplayedAttributes() async {
        let value = course()
        let start = date(2026, 9, 14, 8)
        let end = date(2026, 9, 14, 9)
        let attributes = ClassActivityAttributes(courseID: value.id, courseName: value.name, teacher: value.teacher,
                                                location: value.location, startSection: value.startSection,
                                                endSection: value.endSection, startDate: start, endDate: end)
        XCTAssertTrue(LiveActivityCoordinator.matches(attributes, occurrence: CourseOccurrence(course: value, startDate: start, endDate: end)))
        var edited = value
        edited.location = "B202"
        XCTAssertFalse(LiveActivityCoordinator.matches(attributes, occurrence: CourseOccurrence(course: edited, startDate: start, endDate: end)))
        XCTAssertFalse(LiveActivityCoordinator.matches(attributes, occurrence: CourseOccurrence(course: value, startDate: start, endDate: end.addingTimeInterval(600))))
    }
}
