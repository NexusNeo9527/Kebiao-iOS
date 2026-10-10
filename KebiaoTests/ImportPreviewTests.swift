import XCTest
@testable import Kebiao

final class ImportPreviewTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.firstWeekday = 2
        return value
    }
    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }
    private func table(_ slots: [CourseTimeSlot], periods: [SectionPeriod] = SectionPeriod.defaults) -> Timetable {
        Timetable(semesterStartDate: date(14), timeZoneIdentifier: "GMT", sectionPeriods: periods,
            courses: [Course(name: "导入课程", colorValue: 0x5477D9, timeSlots: slots)])
    }

    func testEveryImportedSlotUsesItsOwnWeekdaysWeeksTeachersAndRooms() throws {
        let first = CourseTimeSlot(teacher: "甲", location: "A101", startSection: 4,
            weekdays: [.friday, .monday], activeWeeks: [1, 2, 3, 5, 7, 8, 9, 11, 13, 14, 15, 17, 19, 20])
        let second = CourseTimeSlot(teacher: "乙", location: "B202", weekdays: [.tuesday],
            startTimeMinutes: 18 * 60, startWeek: 2, endWeek: 6, activeWeeks: [2, 4, 6], durationMinutes: 60)
        let timetable = table([first, second])
        let previews = timetable.courses[0].timeSlots.map { ImportSlotPreview(slot: $0, timetable: timetable) }
        XCTAssertEqual(previews.count, 2)
        XCTAssertEqual(previews[0].weekdaysText, "周一、周五")
        XCTAssertEqual(previews[0].weeksText, "第 1–3、5、7–9、11、13–15、17、19–20 周")
        XCTAssertEqual(previews[1].weekdaysText, "周二")
        XCTAssertEqual(previews[1].weeksText, "第 2、4、6 周")
        XCTAssertEqual(previews.map(\.slot.teacher), ["甲", "乙"])
        XCTAssertEqual(previews.map(\.slot.location), ["A101", "B202"])
        XCTAssertEqual(previews[1].weeklyTimeText, "18:00–19:00")
        let actual = try XCTUnwrap(ScheduleEngine.occurrences(in: timetable, on: date(22)).first)
        XCTAssertEqual(previews[1].weeklyInterval, DateInterval(start: actual.startDate, end: actual.endDate))
    }

    func testPreviewUsesTargetSchoolPeriodsIncludingLunchAndMatchesSchedule() throws {
        let periods = [SectionPeriod(id: 1, startMinutes: 540, endMinutes: 585),
                       SectionPeriod(id: 2, startMinutes: 840, endMinutes: 885)]
        let slot = CourseTimeSlot(startSection: 1, sectionCount: 2, activeWeeks: [1])
        let timetable = table([slot], periods: periods)
        let preview = ImportSlotPreview(slot: slot, timetable: timetable)
        let occurrence = try XCTUnwrap(ScheduleEngine.occurrences(in: timetable, on: date(14)).first)
        XCTAssertEqual(preview.weeklyTimeText, "09:00–14:45")
        XCTAssertEqual(preview.weeklyInterval, DateInterval(start: occurrence.startDate, end: occurrence.endDate))
        XCTAssertEqual(occurrence.endDate.timeIntervalSince(occurrence.startDate), 345 * 60)
    }

    func testCustomStartAndDurationKeepPriorityAndShowNextDay() throws {
        let slot = CourseTimeSlot(startSection: 4, weekdays: [.monday], startTimeMinutes: 23 * 60 + 30,
            activeWeeks: [1], durationMinutes: 120)
        let timetable = table([slot])
        let preview = ImportSlotPreview(slot: slot, timetable: timetable)
        XCTAssertEqual(preview.weeklyTimeText, "23:30–次日 01:30")
        let occurrence = try XCTUnwrap(ScheduleEngine.occurrences(in: timetable, on: date(14)).first)
        XCTAssertEqual(preview.weeklyInterval, DateInterval(start: date(14, 23, 30), end: date(15, 1, 30)))
        XCTAssertEqual(preview.weeklyInterval?.end, occurrence.endDate)
    }

    func testSingleCustomOverrideUsesSchoolStartOrSchoolSpan() throws {
        let customDuration = CourseTimeSlot(startSection: 4, activeWeeks: [1], durationMinutes: 30)
        let customStart = CourseTimeSlot(startSection: 4, startTimeMinutes: 18 * 60, activeWeeks: [1])
        let timetable = table([customDuration, customStart])
        XCTAssertEqual(ImportSlotPreview(slot: customDuration, timetable: timetable).weeklyTimeText, "11:05–11:35")
        XCTAssertEqual(ImportSlotPreview(slot: customStart, timetable: timetable).weeklyTimeText, "18:00–21:40")
        let actual = ScheduleEngine.occurrences(in: timetable, on: date(14))
        for slot in [customDuration, customStart] {
            let occurrence = try XCTUnwrap(actual.first { $0.slotID == slot.id })
            XCTAssertEqual(ImportSlotPreview(slot: slot, timetable: timetable).weeklyInterval,
                           DateInterval(start: occurrence.startDate, end: occurrence.endDate))
        }
    }

    func testSchoolMidnightEndRemainsTheFollowingDay() throws {
        let slot = CourseTimeSlot(sectionCount: 1, activeWeeks: [1])
        let timetable = table([slot], periods: [SectionPeriod(id: 1, startMinutes: 1380, endMinutes: 1440)])
        let preview = ImportSlotPreview(slot: slot, timetable: timetable)
        XCTAssertEqual(preview.weeklyTimeText, "23:00–次日 00:00")
        XCTAssertEqual(preview.weeklyInterval?.end, date(15))
        XCTAssertEqual(ScheduleEngine.occurrences(in: timetable, on: date(14)).first?.endDate, date(15))
    }

    func testMissingTargetPeriodShowsCorrectionInsteadOfUsingGlobalDefaults() {
        let slot = CourseTimeSlot(startSection: 2, sectionCount: 2, activeWeeks: [1])
        let timetable = table([slot], periods: [SectionPeriod(id: 1, startMinutes: 540, endMinutes: 585)])
        let preview = ImportSlotPreview(slot: slot, timetable: timetable)
        XCTAssertFalse(preview.hasMatchingPeriods)
        XCTAssertNil(preview.weeklyInterval)
        XCTAssertEqual(preview.weeklyTimeText, "实际时间待校正")
        XCTAssertTrue(ScheduleEngine.occurrences(in: timetable, on: date(14)).isEmpty)
    }

    func testDatedPreviewRetainsAbsoluteDatesStableIdentityAndSameDayEvents() throws {
        let morning = DatedCourseEvent(startDate: date(14, 1), endDate: date(14, 2))
        let afternoon = DatedCourseEvent(startDate: date(14, 7), endDate: date(14, 8))
        let overnight = DatedCourseEvent(startDate: date(14, 15, 30), endDate: date(14, 17, 30))
        let following = DatedCourseEvent(startDate: date(15, 7), endDate: date(15, 8))
        let slot = CourseTimeSlot(datedEvents: [following, afternoon, overnight, morning])
        var timetable = table([slot])
        timetable.timeZoneIdentifier = "Asia/Shanghai"
        let preview = ImportSlotPreview(slot: slot, timetable: timetable)
        XCTAssertEqual(preview.sortedEvents.map(\.id), [morning.id, afternoon.id, overnight.id, following.id])
        XCTAssertEqual(preview.sortedEvents.count, 4)
        XCTAssertEqual(preview.datedTimeText(for: morning), "2026/09/14 09:00–10:00")
        XCTAssertEqual(preview.datedTimeText(for: overnight), "2026/09/14 23:30–2026/09/15 01:30")
        XCTAssertNil(preview.weeklyInterval)
        XCTAssertEqual(preview.slot.datedEvents, slot.datedEvents)
        XCTAssertEqual(Set(ScheduleEngine.occurrences(in: timetable, on: date(14, 7)).map(\.source)),
                       [.dated(morning.id), .dated(afternoon.id), .dated(overnight.id)])
        timetable.timeZoneIdentifier = "GMT"
        XCTAssertEqual(ImportSlotPreview(slot: slot, timetable: timetable).datedTimeText(for: overnight), "2026/09/14 15:30–17:30")
    }

    func testPDFSourceWeeksRemainReadOnlyWhileCorrectedActualWeeksChange() {
        let original = Course(name: "PDF课程", colorValue: 0x5477D9,
            notes: "原始周次：1-20周\n其他备注", timeSlots: [CourseTimeSlot(activeWeeks: [1, 3, 5])])
        let timetable = table(original.timeSlots)
        var correction = original
        correction.timeSlots[0].activeWeeks = [2, 4, 6]
        XCTAssertEqual(ImportSlotPreview(slot: correction.timeSlots[0], timetable: timetable).weeksText, "第 2、4、6 周")
        XCTAssertEqual(ImportSlotPreview.originalPDFWeekHint(for: correction), "原始周次：1-20周")
        XCTAssertEqual(ImportSlotPreview(slot: original.timeSlots[0], timetable: timetable).weeksText, "第 1、3、5 周")
        XCTAssertEqual(original.timeSlots[0].id, correction.timeSlots[0].id)
        XCTAssertEqual(original.notes, correction.notes)
        XCTAssertNil(ImportSlotPreview.originalPDFWeekHint(for: Course(name: "普通课程", colorValue: 0, timeSlots: original.timeSlots)))
    }
}
