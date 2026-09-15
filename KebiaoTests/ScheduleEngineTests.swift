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
        XCTAssertEqual(course.weekdays, [.tuesday])
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
