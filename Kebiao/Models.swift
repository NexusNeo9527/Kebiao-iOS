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

    static var today: Weekday {
        from(calendarWeekday: Calendar.current.component(.weekday, from: .now))
    }

    func date(inWeekContaining date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        let current = Weekday.from(calendarWeekday: calendar.component(.weekday, from: start))
        return calendar.date(byAdding: .day, value: weekIndex - current.weekIndex, to: start) ?? start
    }
}

struct Course: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var teacher: String
    var location: String
    var startSection: Int
    var sectionCount: Int
    var weekdays: Set<Weekday>
    var colorValue: Int
    var startTimeMinutes: Int?
    var reminderMinutesBefore: Int?

    var color: Color { Color(hex: colorValue) }
    var resolvedStartTimeMinutes: Int {
        startTimeMinutes ?? SectionSchedule.startMinutes(for: startSection)
    }
    var endSection: Int { min(12, startSection + sectionCount - 1) }

    mutating func normalize() {
        startSection = min(12, max(1, startSection))
        sectionCount = min(13 - startSection, max(1, sectionCount))
        if let startTimeMinutes {
            self.startTimeMinutes = min(1439, max(0, startTimeMinutes))
        }
        if let reminderMinutesBefore {
            self.reminderMinutesBefore = min(120, max(1, reminderMinutesBefore))
        }
    }

    static let samples: [Course] = [
        Course(name: "高等数学", teacher: "陈老师", location: "教学楼 A201", startSection: 1, sectionCount: 2, weekdays: [.monday, .wednesday], colorValue: 0xE8795A, startTimeMinutes: nil, reminderMinutesBefore: 10),
        Course(name: "大学英语", teacher: "林老师", location: "教学楼 B103", startSection: 3, sectionCount: 2, weekdays: [.tuesday, .thursday], colorValue: 0x5477D9, startTimeMinutes: nil, reminderMinutesBefore: 10),
        Course(name: "数据结构", teacher: "王老师", location: "实验楼 302", startSection: 5, sectionCount: 2, weekdays: [.monday, .friday], colorValue: 0x3F9D80, startTimeMinutes: nil, reminderMinutesBefore: 10),
        Course(name: "体育", teacher: "张老师", location: "操场", startSection: 7, sectionCount: 2, weekdays: [.wednesday], colorValue: 0xD19436, startTimeMinutes: nil, reminderMinutesBefore: 10)
    ]
}

enum SectionSchedule {
    private static let starts = [480, 535, 610, 665, 840, 895, 970, 1025, 1140, 1195, 1250, 1305]

    static func startMinutes(for section: Int) -> Int {
        starts[min(12, max(1, section)) - 1]
    }
}

extension Color {
    init(hex: Int) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
