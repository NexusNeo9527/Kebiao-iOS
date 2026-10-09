import Foundation

enum TimetableBackupService {
    struct Backup: Codable {
        let format: String
        let version: Int
        let exportedAt: Date
        let collection: TimetableCollection
    }

    static func encode(_ collection: TimetableCollection, at date: Date = .now) throws -> Data {
        try collection.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Backup(format: "KebiaoBackup", version: 2, exportedAt: date, collection: collection))
    }

    static func decode(_ data: Data) throws -> TimetableCollection {
        let object = try JSONSerialization.jsonObject(with: data)
        let result: TimetableCollection
        if let dictionary = object as? [String: Any], dictionary["format"] != nil {
            let backup = try JSONDecoder().decode(Backup.self, from: data)
            guard backup.format == "KebiaoBackup", backup.version == 2 else {
                throw TimetableValidationError.invalid("此备份版本尚不支持，请使用对应版本的课表 App。")
            }
            result = backup.collection
        } else {
            result = try JSONDecoder().decode(TimetableCollection.self, from: data)
        }
        try result.validate()
        return result
    }

    static func calendarData(timetable: Timetable, from start: Date, through end: Date, generatedAt: Date = .now) throws -> Data {
        try timetable.validate()
        let calendar = timetable.calendar
        let first = calendar.startOfDay(for: start)
        guard let last = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)), first < last else {
            throw TimetableValidationError.invalid("请选择有效的导出日期范围。")
        }
        guard calendar.dateComponents([.day], from: first, to: last).day ?? 0 <= 732 else {
            throw TimetableValidationError.invalid("一次最多导出两年的课程。")
        }
        let occurrences = ScheduleEngine.occurrences(in: timetable, from: first, to: last)
            .filter { $0.startDate >= first && $0.startDate < last }
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Kebiao//Timetable 1.4//ZH", "CALSCALE:GREGORIAN", "X-WR-CALNAME:\(escape(timetable.name))"]
        for occurrence in occurrences {
            let course = occurrence.course
            let description = [course.teacher.isEmpty ? nil : "教师：\(course.teacher)", course.notes]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
            lines += ["BEGIN:VEVENT", "UID:\(escape(occurrence.id))@kebiao.local", "DTSTAMP:\(timestamp(generatedAt))",
                      "DTSTART:\(timestamp(occurrence.startDate))", "DTEND:\(timestamp(occurrence.endDate))",
                      "SUMMARY:\(escape(course.name))", "LOCATION:\(escape(course.location))", "DESCRIPTION:\(escape(description))", "END:VEVENT"]
        }
        lines.append("END:VCALENDAR")
        return Data((lines.map(fold).joined(separator: "\r\n") + "\r\n").utf8)
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }
    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
    }
    // Fold at UTF-8 boundaries, including the continuation space in the 75-octet limit.
    private static func fold(_ line: String) -> String {
        var output = ""
        var length = 0
        for scalar in line.unicodeScalars {
            let value = String(scalar)
            let count = value.utf8.count
            if length + count > 75 { output += "\r\n "; length = 1 }
            output += value; length += count
        }
        return output
    }
}
