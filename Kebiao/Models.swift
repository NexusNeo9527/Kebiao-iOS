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

    static var today: Weekday {
        Weekday(rawValue: Calendar.current.component(.weekday, from: .now)) ?? .monday
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

    var color: Color { Color(hex: colorValue) }

    static let samples: [Course] = [
        Course(name: "高等数学", teacher: "陈老师", location: "教学楼 A201", startSection: 1, sectionCount: 2, weekdays: [.monday, .wednesday], colorValue: 0xE8795A),
        Course(name: "大学英语", teacher: "林老师", location: "教学楼 B103", startSection: 3, sectionCount: 2, weekdays: [.tuesday, .thursday], colorValue: 0x5477D9),
        Course(name: "数据结构", teacher: "王老师", location: "实验楼 302", startSection: 5, sectionCount: 2, weekdays: [.monday, .friday], colorValue: 0x3F9D80),
        Course(name: "体育", teacher: "张老师", location: "操场", startSection: 7, sectionCount: 2, weekdays: [.wednesday], colorValue: 0xD19436)
    ]
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
