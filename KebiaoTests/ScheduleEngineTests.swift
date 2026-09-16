import XCTest
@testable import Kebiao

final class ScheduleEngineTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    func testSundayMapsFromCalendarWithoutChangingStoredRawValue() {
        XCTAssertEqual(Weekday.sunday.rawValue, 8)
        XCTAssertEqual(Weekday.from(calendarWeekday: 1), .sunday)
        XCTAssertEqual(Weekday.from(calendarWeekday: 2), .monday)
    }

    func testWeekDatesStayInWeekContainingTuesday() throws {
        let tuesday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 15)))
        let monday = ScheduleEngine.date(for: .monday, inWeekContaining: tuesday, calendar: calendar)
        let sunday = ScheduleEngine.date(for: .sunday, inWeekContaining: tuesday, calendar: calendar)

        XCTAssertEqual(calendar.component(.day, from: monday), 14)
        XCTAssertEqual(calendar.component(.day, from: sunday), 20)
    }

    func testCourseNormalizationPreventsSectionOverflow() {
        var course = makeCourse(startSection: 12, sectionCount: 4)
        course.normalize()

        XCTAssertEqual(course.sectionCount, 1)
        XCTAssertEqual(course.endSection, 12)
    }

    func testLegacyCourseJSONDecodesWithoutReminderFields() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "name": "旧课程",
          "teacher": "老师",
          "location": "教室",
          "startSection": 3,
          "sectionCount": 2,
          "weekdays": [3],
          "colorValue": 5535705
        }
        """.data(using: .utf8)!

        let course = try JSONDecoder().decode(Course.self, from: json)
        XCTAssertNil(course.startTimeMinutes)
        XCTAssertNil(course.reminderMinutesBefore)
        XCTAssertNil(course.startWeek)
        XCTAssertNil(course.credits)
        XCTAssertEqual(course.weekdays, [.tuesday])
    }

    func testAcademicWeekStartsOnSemesterWeek() throws {
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 16)))
        XCTAssertEqual(ScheduleEngine.academicWeekNumber(for: date, calendar: calendar), 3)
    }

    func testCSVImportMapsCommonChineseSchoolHeaders() throws {
        let csv = """
        课程名称,教师,教室,星期,开始节次,节数,上课周数,开始时间
        操作系统,张老师,弘毅楼A310,周一、周三,5,2,3-16,13:30
        """.data(using: .utf8)!

        let result = try ScheduleImportService.parseCSV(csv)
        let course = try XCTUnwrap(result.0.first)
        XCTAssertEqual(course.name, "操作系统")
        XCTAssertEqual(course.weekdays, [.monday, .wednesday])
        XCTAssertEqual(course.startWeek, 3)
        XCTAssertEqual(course.endWeek, 16)
        XCTAssertEqual(course.startTimeMinutes, 810)
    }

    func testJSONImportAcceptsCoursesEnvelopeAndNumericWeekdays() throws {
        let json = """
        {"courses":[{"name":"软件设计模式","teacher":"李老师","location":"B207","weekdays":[2,5],"startSection":7,"sectionCount":2}]}
        """.data(using: .utf8)!

        let result = try ScheduleImportService.parseJSON(json)
        let course = try XCTUnwrap(result.0.first)
        XCTAssertEqual(course.weekdays, [.tuesday, .friday])
        XCTAssertEqual(course.startSection, 7)
    }

    func testICSImportUsesRecurringWeekdaysAndLocation() throws {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        SUMMARY:数据结构
        DTSTART:20260916T101000
        DTEND:20260916T120000
        LOCATION:实验楼302
        DESCRIPTION:教师：王老师
        RRULE:FREQ=WEEKLY;BYDAY=MO,WE
        END:VEVENT
        END:VCALENDAR
        """.data(using: .utf8)!

        let result = try ScheduleImportService.parseICS(ics)
        let course = try XCTUnwrap(result.0.first)
        XCTAssertEqual(course.weekdays, [.monday, .wednesday])
        XCTAssertEqual(course.location, "实验楼302")
        XCTAssertEqual(course.teacher, "王老师")
    }

    func testSchoolTextImportAcceptsZhengfangCopiedTable() throws {
        let text = """
        课程名称\t任课教师\t上课地点\t上课时间
        高等数学\t陈老师\t教学楼A201\t周一第1-2节 1-16周
        """

        let preview = try ScheduleImportService.parseSchoolText(text, sourceName: "正方教务")
        let course = try XCTUnwrap(preview.courses.first)
        XCTAssertEqual(preview.format, .text)
        XCTAssertEqual(course.name, "高等数学")
        XCTAssertEqual(course.teacher, "陈老师")
        XCTAssertEqual(course.location, "教学楼A201")
        XCTAssertEqual(course.weekdays, [.monday])
        XCTAssertEqual(course.startSection, 1)
        XCTAssertEqual(course.sectionCount, 2)
        XCTAssertEqual(course.startWeek, 1)
        XCTAssertEqual(course.endWeek, 16)
    }

    private func makeCourse(startSection: Int, sectionCount: Int) -> Course {
        Course(
            name: "测试课程",
            teacher: "老师",
            location: "教室",
            startSection: startSection,
            sectionCount: sectionCount,
            weekdays: [.monday],
            colorValue: 0x5477D9,
            startTimeMinutes: 480,
            reminderMinutesBefore: 10
        )
    }
}
