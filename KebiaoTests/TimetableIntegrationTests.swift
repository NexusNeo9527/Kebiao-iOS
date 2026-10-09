import ActivityKit
import XCTest
@testable import Kebiao

@MainActor
final class TimetableIntegrationTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.firstWeekday = 2
        return value
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func timetable(name: String = "秋季课表", courses: [Course]? = nil) -> Timetable {
        let slot = CourseTimeSlot(teacher: "王老师", location: "A301", startSection: 5,
            weekdays: [.friday], startTimeMinutes: 840, durationMinutes: 50)
        return Timetable(name: name, semesterStartDate: date(5, 0), weekCount: 20,
            timeZoneIdentifier: "GMT", courses: courses ?? [Course(name: "操作系统", colorValue: 0x5477D9, timeSlots: [slot])])
    }

    func testServicesDistinguishIdenticalCourseAndSlotInDifferentTimetables() throws {
        let first = timetable()
        let second = timetable(name: "另一学期", courses: first.courses)
        let original = try XCTUnwrap(ScheduleEngine.occurrences(in: first, on: date(9, 0)).first)
        let other = try XCTUnwrap(ScheduleEngine.occurrences(in: second, on: date(9, 0)).first)
        XCTAssertEqual(original.courseID, other.courseID)
        XCTAssertEqual(original.slotID, other.slotID)
        XCTAssertNotEqual(ReminderScheduler.notificationIdentifier(for: original),
                          ReminderScheduler.notificationIdentifier(for: other))
        XCTAssertTrue(LiveActivityCoordinator.matches(attributes(for: original), occurrence: original))
        XCTAssertFalse(LiveActivityCoordinator.matches(attributes(for: original), occurrence: other))
        var wrongTimeZone = attributes(for: original)
        wrongTimeZone.timeZoneIdentifier = "Asia/Shanghai"
        XCTAssertFalse(LiveActivityCoordinator.matches(wrongTimeZone, occurrence: original))
    }

    func testMultipleSlotsProduceSeparateNotificationsAndSelectNextActualSlot() throws {
        let morning = CourseTimeSlot(teacher: "甲", location: "A301", startSection: 1,
            weekdays: [.friday], startTimeMinutes: 540, reminderMinutesBefore: 10, durationMinutes: 50)
        let afternoon = CourseTimeSlot(teacher: "乙", location: "B202", startSection: 5,
            weekdays: [.friday], startTimeMinutes: 840, reminderMinutesBefore: 15, durationMinutes: 60)
        let table = timetable(courses: [Course(name: "操作系统", colorValue: 0x5477D9, timeSlots: [morning, afternoon])])
        let occurrences = ScheduleEngine.occurrences(in: table, on: date(9, 0))
        XCTAssertEqual(occurrences.count, 2)
        XCTAssertEqual(Set(occurrences.map(\.slotID)), [morning.id, afternoon.id])
        let reminders = ScheduleEngine.reminders(in: table, after: date(9, 8)).filter {
            calendar.isDate($0.occurrence.startDate, inSameDayAs: date(9, 0))
        }
        XCTAssertEqual(reminders.map(\.fireDate), [date(9, 8, 50), date(9, 13, 45)])
        XCTAssertEqual(Set(reminders.map { ReminderScheduler.notificationIdentifier(for: $0.occurrence) }).count, 2)
        let plan = LiveActivityPlan.make(timetable: table, at: date(9, 13, 29))
        XCTAssertEqual(plan.occurrenceToDisplay?.slotID, afternoon.id)
        XCTAssertEqual(plan.occurrenceToDisplay?.teacher, "乙")
        XCTAssertEqual(plan.occurrenceToDisplay?.location, "B202")
    }

    func testSwitchingTimetableEndsPreviewAndStartsOnlyNewTimetable() async throws {
        let first = timetable()
        let second = timetable(name: "第二课表", courses: first.courses)
        let fake = TimetableActivityFake()
        let controller = LiveActivityController(client: fake.client)
        try await controller.preview(timetable: first, at: date(9, 13, 29))
        let previewID = try XCTUnwrap(controller.status.activityID)
        await controller.refresh(timetable: second, enabled: true, at: date(9, 13, 29))
        XCTAssertTrue(fake.endedIDs.contains(previewID))
        XCTAssertEqual(fake.requests.last?.timetableID, second.id)
        XCTAssertEqual(fake.existing.count, 1)
        XCTAssertEqual(controller.status.phase, .active)
    }

    func testSuspendedOldTimetableRefreshCannotCreateActivityAfterSwitch() async throws {
        let first = timetable()
        let second = timetable(name: "第二课表", courses: first.courses)
        let oldOccurrence = try XCTUnwrap(ScheduleEngine.occurrences(in: first, on: date(9, 0)).first)
        let fake = TimetableActivityFake(existing: [LiveActivityHandle(id: "old", attributes: attributes(for: oldOccurrence), state: .active)])
        let controller = LiveActivityController(client: fake.client)
        let started = expectation(description: "Old timetable cleanup suspended")
        var continuation: CheckedContinuation<Void, Never>?
        fake.onEnd = {
            await withCheckedContinuation { value in continuation = value; started.fulfill() }
        }
        let oldTask = Task { await controller.refresh(timetable: first, enabled: true, at: date(9, 13, 29)) }
        await fulfillment(of: [started], timeout: 2)
        fake.onEnd = nil
        await controller.refresh(timetable: second, enabled: true, at: date(9, 13, 29))
        continuation?.resume()
        await oldTask.value
        XCTAssertEqual(fake.requests.map(\.timetableID), [second.id])
        XCTAssertEqual(controller.status.phase, .active)
        XCTAssertEqual(fake.existing.count, 1)
    }

    func testNativeMultiSlotJSONSuppliesMissingIDsAndColorWithoutFlattening() throws {
        let json = #"""
        [{"name":"高等数学","timeSlots":[
          {"teacher":"甲","location":"A301","weekdays":[2],"startSection":1,"sectionCount":2,"activeWeeks":[1,3]},
          {"teacher":"乙","location":"B202","weekdays":[6],"startSection":7,"sectionCount":1,"startTimeMinutes":900}
        ]}]
        """#
        let imported = try ScheduleImportService.parseJSON(Data(json.utf8))
        let course = try XCTUnwrap(imported.0.first)
        XCTAssertTrue(imported.1.isEmpty)
        XCTAssertEqual(course.timeSlots.count, 2)
        XCTAssertEqual(Set(course.timeSlots.map(\.id)).count, 2)
        XCTAssertEqual(course.timeSlots[0].weekdays, [.monday])
        XCTAssertEqual(course.timeSlots[0].activeWeeks, [1, 3])
        XCTAssertEqual(course.timeSlots[1].weekdays, [.friday])
        XCTAssertEqual(course.timeSlots[1].location, "B202")
        XCTAssertEqual(course.timeSlots[1].startTimeMinutes, 900)
    }

    func testImportedSixPeriodsUseTargetBellTimesAcrossLunch() throws {
        let preview = try ScheduleImportService.parseSchoolText("课程名称\t星期\t节次\t周数\t教室\n集中实训\t周一\t1-6\t1-2\tA301")
        let course = try XCTUnwrap(preview.courses.first)
        XCTAssertEqual(course.sectionCount, 6)
        XCTAssertNil(course.timeSlots[0].durationMinutes)
        var table = timetable(courses: preview.courses)
        table.sectionPeriods = [
            SectionPeriod(id: 1, startMinutes: 480, endMinutes: 525),
            SectionPeriod(id: 2, startMinutes: 535, endMinutes: 580),
            SectionPeriod(id: 3, startMinutes: 590, endMinutes: 635),
            SectionPeriod(id: 4, startMinutes: 645, endMinutes: 690),
            SectionPeriod(id: 5, startMinutes: 840, endMinutes: 885),
            SectionPeriod(id: 6, startMinutes: 895, endMinutes: 940)
        ]
        let occurrence = try XCTUnwrap(ScheduleEngine.occurrences(in: table, on: date(5, 0)).first)
        XCTAssertEqual(occurrence.startDate, date(5, 8))
        XCTAssertEqual(occurrence.endDate, date(5, 15, 40))
    }

    func testImportPreviewFindsLateWeekInSecondSlot() throws {
        let unused = CourseTimeSlot(weekdays: [.monday], activeWeeks: [])
        let late = CourseTimeSlot(startSection: 3, weekdays: [.friday], activeWeeks: [27])
        let course = Course(name: "实训", colorValue: 0x5477D9, timeSlots: [unused, late])
        let table = timetable(courses: [course])
        let preview = ScheduleImportPreview(sourceName: "课程.json", format: .json, courses: [course], warnings: [])
        let result = preview.timetablePreviewDate(reference: date(14, 9), in: table)
        let expected = try XCTUnwrap(calendar.date(byAdding: .day, value: 26 * 7 + 4, to: date(5, 0)))
        XCTAssertTrue(calendar.isDate(result, inSameDayAs: expected))
    }

    func testImportPreviewSkipsCancelledDayAndFindsMovedOccurrence() throws {
        let slot = CourseTimeSlot(startSection: 5, weekdays: [.friday], activeWeeks: [1, 2])
        var course = Course(name: "实验", colorValue: 0x5477D9, timeSlots: [slot])
        course.exceptions = [
            CourseException(slotID: slot.id, source: .weekly("2026-10-09"), action: .cancelled),
            CourseException(slotID: slot.id, source: .weekly("2026-10-16"), action: .replaced,
                startDate: date(15, 16, 30), endDate: date(15, 17, 10), location: "B202")
        ]
        let table = timetable(courses: [course])
        let preview = ScheduleImportPreview(sourceName: "课程.json", format: .json, courses: [course], warnings: [])
        let result = preview.timetablePreviewDate(reference: date(26, 9), in: table)
        XCTAssertTrue(calendar.isDate(result, inSameDayAs: date(15, 0)))
        let occurrence = try XCTUnwrap(ScheduleEngine.occurrences(in: table, on: result).first)
        XCTAssertEqual(occurrence.startDate, date(15, 16, 30))
        XCTAssertEqual(occurrence.location, "B202")
    }

    private func attributes(for occurrence: CourseOccurrence) -> ClassActivityAttributes {
        let course = occurrence.course
        return ClassActivityAttributes(courseID: course.id, courseName: course.name, teacher: occurrence.teacher,
            location: occurrence.location, startSection: course.startSection, endSection: course.endSection,
            startDate: occurrence.startDate, endDate: occurrence.endDate, occurrenceID: occurrence.id,
            timeZoneIdentifier: occurrence.timeZoneIdentifier)
    }
}

@MainActor
private final class TimetableActivityFake {
    var existing: [LiveActivityHandle]
    var requests: [CourseOccurrence] = []
    var endedIDs: [String] = []
    var onEnd: (() async -> Void)?

    init(existing: [LiveActivityHandle] = []) { self.existing = existing }

    var client: LiveActivityClient {
        LiveActivityClient(authorized: { true }, activities: { self.existing }, request: { occurrence in
            self.requests.append(occurrence)
            let course = occurrence.course
            let handle = LiveActivityHandle(id: UUID().uuidString,
                attributes: ClassActivityAttributes(courseID: course.id, courseName: course.name,
                    teacher: occurrence.teacher, location: occurrence.location, startSection: course.startSection,
                    endSection: course.endSection, startDate: occurrence.startDate, endDate: occurrence.endDate,
                    occurrenceID: occurrence.id, timeZoneIdentifier: occurrence.timeZoneIdentifier), state: .active)
            self.existing.append(handle)
            return handle
        }, end: { handle in
            await self.onEnd?()
            self.endedIDs.append(handle.id)
            self.existing.removeAll { $0.id == handle.id }
        })
    }
}
