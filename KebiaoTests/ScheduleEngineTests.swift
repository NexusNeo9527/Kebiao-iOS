import XCTest
import UIKit
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

    func testRightSwipeKeepsPreviousWeekDirectionWhenPredictionReboundsLeft() {
        let delta = WeekSwipeDecision.weekDelta(
            translation: CGSize(width: 84, height: 6),
            predictedEndTranslation: CGSize(width: -130, height: 8)
        )

        XCTAssertEqual(delta, -1)
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

    func testSchoolTextImportAcceptsKeyValueBlocks() throws {
        let text = """
        课程名：数据结构
        任课老师：王老师
        教学地点：实验楼302
        课程安排：周三第3-4节 2-18周

        课程名：大学英语
        任课老师：林老师
        教学地点：教学楼B103
        课程安排：周五第5-6节 1-16周
        """

        let preview = try ScheduleImportService.parseSchoolText(text, sourceName: "强智教务")
        XCTAssertEqual(preview.courses.count, 2)
        XCTAssertEqual(preview.courses[0].weekdays, [.wednesday])
        XCTAssertEqual(preview.courses[0].startSection, 3)
        XCTAssertEqual(preview.courses[0].sectionCount, 2)
        XCTAssertEqual(preview.courses[0].startWeek, 2)
        XCTAssertEqual(preview.courses[0].endWeek, 18)
    }

    func testHTMLImportAcceptsSavedSchoolTable() throws {
        let html = """
        <table>
          <tr><th>课程名称</th><th>教师</th><th>上课地点</th><th>上课时间</th></tr>
          <tr><td>操作系统</td><td>张老师</td><td>弘毅楼A310</td><td>周二第5-6节 3-16周</td></tr>
        </table>
        """

        let preview = try ScheduleImportService.parseHTML(html, sourceName: "青果教务.html")
        let course = try XCTUnwrap(preview.courses.first)
        XCTAssertEqual(preview.format, .html)
        XCTAssertEqual(course.name, "操作系统")
        XCTAssertEqual(course.weekdays, [.tuesday])
        XCTAssertEqual(course.location, "弘毅楼A310")
    }

    func testSchoolPortalPayloadAcceptsLoggedInTimetableHTML() throws {
        let html = """
        <table>
          <tr><th>课程名称</th><th>任课教师</th><th>上课地点</th><th>上课时间</th></tr>
          <tr><td>编译原理</td><td>刘老师</td><td>信工楼B205</td><td>周四第3-4节 2-17周</td></tr>
        </table>
        """

        let preview = try ScheduleImportService.parseSchoolPortalPayload(html, sourceName: "学校教务系统")
        let course = try XCTUnwrap(preview.courses.first)
        XCTAssertEqual(preview.format, .portal)
        XCTAssertEqual(course.name, "编译原理")
        XCTAssertEqual(course.weekdays, [.thursday])
        XCTAssertEqual(course.startWeek, 2)
        XCTAssertEqual(course.endWeek, 17)
    }

    func testPDFImportExtractsTextTimetable() throws {
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            context.beginPage()
            let text = """
            课程名称,任课教师,上课地点,上课时间
            计算机网络,赵老师,实验楼401,周二第7-8节 1-16周
            """
            text.draw(
                in: bounds.insetBy(dx: 36, dy: 36),
                withAttributes: [.font: UIFont.systemFont(ofSize: 16)]
            )
        }

        let preview = try ScheduleImportService.parsePDF(data: data, sourceName: "学生课表.pdf")
        let course = try XCTUnwrap(preview.courses.first)
        XCTAssertEqual(preview.format, .pdf)
        XCTAssertEqual(course.name, "计算机网络")
        XCTAssertEqual(course.teacher, "赵老师")
        XCTAssertEqual(course.location, "实验楼401")
        XCTAssertEqual(course.weekdays, [.tuesday])
        XCTAssertEqual(course.startSection, 7)
        XCTAssertEqual(course.sectionCount, 2)
    }

    func testPDFImportReassemblesCourseFieldsExtractedOnSeparateLines() throws {
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            context.beginPage()
            let lines = [
                "课程名称", "计算机组成原理",
                "任课教师", "周老师",
                "上课地点", "博学楼A203",
                "上课时间", "周三", "第3-4节", "2-18周"
            ]
            for (index, line) in lines.enumerated() {
                line.draw(
                    at: CGPoint(x: 36, y: 36 + CGFloat(index) * 28),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 16)]
                )
            }
        }

        let preview = try ScheduleImportService.parsePDF(data: data, sourceName: "分行课表.pdf")
        let course = try XCTUnwrap(preview.courses.first)
        XCTAssertEqual(course.name, "计算机组成原理")
        XCTAssertEqual(course.teacher, "周老师")
        XCTAssertEqual(course.location, "博学楼A203")
        XCTAssertEqual(course.weekdays, [.wednesday])
        XCTAssertEqual(course.startSection, 3)
        XCTAssertEqual(course.sectionCount, 2)
        XCTAssertEqual(course.startWeek, 2)
        XCTAssertEqual(course.endWeek, 18)
    }

    func testPDFImportUsesOCRForImageOnlyTimetable() throws {
        let imageSize = CGSize(width: 1200, height: 800)
        let image = UIGraphicsImageRenderer(size: imageSize).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: imageSize))
            let text = """
            course: Networks
            teacher: Lee
            location: B201
            weekday: Monday
            section: 3-4
            weeks: 2-18
            """
            text.draw(
                in: CGRect(x: 70, y: 70, width: 1060, height: 660),
                withAttributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: 42, weight: .medium),
                    .foregroundColor: UIColor.black
                ]
            )
        }
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            context.beginPage()
            image.draw(in: bounds.insetBy(dx: 20, dy: 20))
        }

        let diagnosis: String
        do {
            let preview = try ScheduleImportService.parsePDF(data: data, sourceName: "扫描课表.pdf")
            diagnosis = preview.courses.map {
                "name=\($0.name),teacher=\($0.teacher),location=\($0.location),weekdays=\($0.weekdays),section=\($0.startSection)-\($0.endSection),weeks=\($0.startWeek.map(String.init) ?? "nil")-\($0.endWeek.map(String.init) ?? "nil")"
            }.joined(separator: " | ")
        } catch {
            diagnosis = "error=\(error.localizedDescription)"
        }
        fatalError("[DEBUG-OCR-PDF] \(diagnosis)")
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
