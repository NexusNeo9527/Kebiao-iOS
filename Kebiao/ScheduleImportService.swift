import Foundation

enum ScheduleImportFormat: String, CaseIterable, Identifiable {
    case csv = "CSV"
    case json = "JSON"
    case ics = "ICS"

    var id: String { rawValue }
}

struct ScheduleImportPreview {
    let sourceName: String
    let format: ScheduleImportFormat
    let courses: [Course]
    let warnings: [String]
}

enum ScheduleImportError: LocalizedError {
    case unreadableFile
    case unsupportedFormat
    case emptyResult
    case malformed(String)

    var errorDescription: String? {
        switch self {
        case .unreadableFile: "无法读取所选文件。"
        case .unsupportedFormat: "暂不支持这种文件格式，请选择 CSV、JSON 或 ICS。"
        case .emptyResult: "文件中没有找到可导入的课程。"
        case .malformed(let detail): "文件内容无法识别：\(detail)"
        }
    }
}

enum ScheduleImportService {
    static func load(url: URL) throws -> ScheduleImportPreview {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { url.stopAccessingSecurityScopedResource() }
        }

        guard let data = try? Data(contentsOf: url) else {
            throw ScheduleImportError.unreadableFile
        }

        let extensionName = url.pathExtension.lowercased()
        let format: ScheduleImportFormat
        let result: ([Course], [String])
        switch extensionName {
        case "csv":
            format = .csv
            result = try parseCSV(data)
        case "json":
            format = .json
            result = try parseJSON(data)
        case "ics", "ical":
            format = .ics
            result = try parseICS(data)
        default:
            throw ScheduleImportError.unsupportedFormat
        }

        guard !result.0.isEmpty else { throw ScheduleImportError.emptyResult }
        return ScheduleImportPreview(
            sourceName: url.lastPathComponent,
            format: format,
            courses: result.0,
            warnings: result.1
        )
    }

    static func parseCSV(_ data: Data) throws -> ([Course], [String]) {
        let gb18030 = String.Encoding(rawValue: 0x80000632)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: gb18030) else {
            throw ScheduleImportError.malformed("无法识别文字编码")
        }
        let rows = parseCSVRows(text)
        guard let header = rows.first, header.count > 1 else {
            throw ScheduleImportError.malformed("缺少表头")
        }

        let keys = header.map(normalizedKey)
        var courses: [Course] = []
        var warnings: [String] = []
        for (offset, row) in rows.dropFirst().enumerated() where row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            var record: [String: String] = [:]
            for index in keys.indices where index < row.count {
                record[keys[index]] = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let course = course(from: record) {
                courses.append(course)
            } else {
                warnings.append("第 \(offset + 2) 行缺少课程名称或星期，已跳过")
            }
        }
        return (courses, warnings)
    }

    static func parseJSON(_ data: Data) throws -> ([Course], [String]) {
        guard let value = try? JSONSerialization.jsonObject(with: data) else {
            throw ScheduleImportError.malformed("JSON 语法错误")
        }
        let objects: [[String: Any]]
        if let array = value as? [[String: Any]] {
            objects = array
        } else if let root = value as? [String: Any], let array = root["courses"] as? [[String: Any]] {
            objects = array
        } else {
            throw ScheduleImportError.malformed("需要课程数组，或包含 courses 数组的对象")
        }

        var courses: [Course] = []
        var warnings: [String] = []
        for (index, object) in objects.enumerated() {
            var record: [String: String] = [:]
            for (key, value) in object {
                record[normalizedKey(key)] = stringValue(value)
            }
            if let course = course(from: record) {
                courses.append(course)
            } else {
                warnings.append("第 \(index + 1) 条缺少课程名称或星期，已跳过")
            }
        }
        return (courses, warnings)
    }

    static func parseICS(_ data: Data) throws -> ([Course], [String]) {
        guard let raw = String(data: data, encoding: .utf8) else {
            throw ScheduleImportError.malformed("ICS 不是 UTF-8 编码")
        }
        let unfolded = raw.replacingOccurrences(of: "\r\n ", with: "")
            .replacingOccurrences(of: "\n ", with: "")
        let blocks = unfolded.components(separatedBy: "BEGIN:VEVENT").dropFirst()
        var courses: [Course] = []
        var warnings: [String] = []

        for (index, block) in blocks.enumerated() {
            let body = block.components(separatedBy: "END:VEVENT").first ?? block
            let lines = body.components(separatedBy: .newlines)
            let summary = icsValue("SUMMARY", in: lines)
            let location = icsValue("LOCATION", in: lines)
            let description = icsValue("DESCRIPTION", in: lines)
            guard !summary.isEmpty, let start = icsDate("DTSTART", in: lines) else {
                warnings.append("第 \(index + 1) 个日历事件缺少标题或时间，已跳过")
                continue
            }
            let end = icsDate("DTEND", in: lines) ?? start.addingTimeInterval(50 * 60)
            let startMinutes = Calendar.current.component(.hour, from: start) * 60 + Calendar.current.component(.minute, from: start)
            let duration = max(45, Int(end.timeIntervalSince(start) / 60))
            let weekdays = icsWeekdays(lines: lines, fallback: start)
            let startSection = nearestSection(to: startMinutes)
            let count = min(4, max(1, Int(round(Double(duration) / 50.0))))
            courses.append(Course(
                name: summary,
                teacher: teacher(from: description),
                location: location,
                startSection: startSection,
                sectionCount: min(count, 13 - startSection),
                weekdays: weekdays,
                colorValue: palette[courses.count % palette.count],
                startTimeMinutes: startMinutes,
                reminderMinutesBefore: 10,
                notes: description.isEmpty ? nil : description
            ))
        }
        return (courses, warnings)
    }

    private static let palette = [0xFF4B68, 0x29B8AF, 0x7B68C8, 0xF29F36, 0x438DDB, 0xE96A42]

    private static func course(from record: [String: String]) -> Course? {
        let name = value(in: record, keys: ["coursename", "course", "name", "课程名称", "课程", "科目"])
        let dayText = value(in: record, keys: ["weekday", "weekdays", "day", "星期", "星期几", "周几"])
        let weekdays = parseWeekdays(dayText)
        guard !name.isEmpty, !weekdays.isEmpty else { return nil }

        let section = intValue(value(in: record, keys: ["startsection", "section", "period", "开始节次", "节次", "开始节数"])) ?? 1
        let count = intValue(value(in: record, keys: ["sectioncount", "duration", "节数", "连续节数"])) ?? 2
        let time = timeMinutes(value(in: record, keys: ["starttime", "time", "开始时间", "上课时间"]))
        let weeks = weekRange(value(in: record, keys: ["weeks", "weekrange", "周数", "上课周数"]))
        let colorIndex = name.utf8.reduce(0) { ($0 + Int($1)) % palette.count }
        let color = colorValue(value(in: record, keys: ["color", "颜色"])) ?? palette[colorIndex]
        return Course(
            name: name,
            teacher: value(in: record, keys: ["teacher", "instructor", "老师", "教师"]),
            location: value(in: record, keys: ["location", "classroom", "room", "教室", "地点"]),
            startSection: min(12, max(1, section)),
            sectionCount: min(4, max(1, count)),
            weekdays: weekdays,
            colorValue: color,
            startTimeMinutes: time,
            reminderMinutesBefore: intValue(value(in: record, keys: ["reminder", "提醒", "提前提醒"])) ?? 10,
            startWeek: weeks?.0,
            endWeek: weeks?.1,
            credits: Double(value(in: record, keys: ["credits", "credit", "学分"])),
            notes: optional(value(in: record, keys: ["notes", "note", "备注"]))
        )
    }

    private static func parseCSVRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        let characters = Array(text.replacingOccurrences(of: "\r\n", with: "\n"))
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if quoted, index + 1 < characters.count, characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 1
                } else {
                    quoted.toggle()
                }
            } else if character == ",", !quoted {
                row.append(field)
                field = ""
            } else if character == "\n", !quoted {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(character)
            }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    private static func parseWeekdays(_ text: String) -> Set<Weekday> {
        let normalized = text.lowercased()
            .replacingOccurrences(of: "星期", with: "周")
            .replacingOccurrences(of: "礼拜", with: "周")
        let mappings: [(Weekday, [String])] = [
            (.monday, ["周一", "monday", "mon"]),
            (.tuesday, ["周二", "tuesday", "tue"]),
            (.wednesday, ["周三", "wednesday", "wed"]),
            (.thursday, ["周四", "thursday", "thu"]),
            (.friday, ["周五", "friday", "fri"]),
            (.saturday, ["周六", "saturday", "sat"]),
            (.sunday, ["周日", "周天", "sunday", "sun"])
        ]
        var result = Set(mappings.compactMap { day, aliases in aliases.contains(where: normalized.contains) ? day : nil })
        let numericTokens = normalized.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
        for number in numericTokens where (1...7).contains(number) {
            result.insert(Weekday.allCases[number - 1])
        }
        return result
    }

    private static func weekRange(_ text: String) -> (Int, Int)? {
        let numbers = text.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
        guard let first = numbers.first else { return nil }
        return (first, max(first, numbers.dropFirst().first ?? first))
    }

    private static func timeMinutes(_ text: String) -> Int? {
        let parts = text.components(separatedBy: ":").compactMap(Int.init)
        guard parts.count >= 2 else { return nil }
        return min(1439, max(0, parts[0] * 60 + parts[1]))
    }

    private static func colorValue(_ text: String) -> Int? {
        let value = text.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        return Int(value, radix: 16)
    }

    private static func intValue(_ text: String) -> Int? {
        text.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init).first
    }

    private static func value(in record: [String: String], keys: [String]) -> String {
        for key in keys {
            if let value = record[normalizedKey(key)], !value.isEmpty { return value }
        }
        return ""
    }

    private static func optional(_ value: String) -> String? { value.isEmpty ? nil : value }

    private static func normalizedKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{feff}", with: "")
    }

    private static func stringValue(_ value: Any) -> String {
        if let string = value as? String { return string }
        if let array = value as? [Any] { return array.map(stringValue).joined(separator: ",") }
        return String(describing: value)
    }

    private static func icsValue(_ key: String, in lines: [String]) -> String {
        guard let line = lines.first(where: { $0.uppercased().hasPrefix(key + ":") || $0.uppercased().hasPrefix(key + ";") }),
              let separator = line.firstIndex(of: ":") else { return "" }
        return String(line[line.index(after: separator)...])
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
    }

    private static func icsDate(_ key: String, in lines: [String]) -> Date? {
        let value = icsValue(key, in: lines)
        let formats = ["yyyyMMdd'T'HHmmss'Z'", "yyyyMMdd'T'HHmmss", "yyyyMMdd'T'HHmm", "yyyyMMdd"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            formatter.timeZone = format.hasSuffix("'Z'") ? TimeZone(secondsFromGMT: 0) : .current
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private static func icsWeekdays(lines: [String], fallback date: Date) -> Set<Weekday> {
        let rule = icsValue("RRULE", in: lines).uppercased()
        let mappings: [(String, Weekday)] = [("MO", .monday), ("TU", .tuesday), ("WE", .wednesday), ("TH", .thursday), ("FR", .friday), ("SA", .saturday), ("SU", .sunday)]
        let byDayValue = rule.components(separatedBy: ";")
            .first(where: { $0.hasPrefix("BYDAY=") })?
            .dropFirst("BYDAY=".count) ?? ""
        let dayCodes = Set(byDayValue.split(separator: ",").map(String.init))
        let days = Set(mappings.compactMap { dayCodes.contains($0.0) ? $0.1 : nil })
        if !days.isEmpty { return days }
        return [Weekday.from(calendarWeekday: Calendar.current.component(.weekday, from: date))]
    }

    private static func nearestSection(to minutes: Int) -> Int {
        (1...12).min { abs(SectionSchedule.startMinutes(for: $0) - minutes) < abs(SectionSchedule.startMinutes(for: $1) - minutes) } ?? 1
    }

    private static func teacher(from description: String) -> String {
        for prefix in ["教师：", "老师：", "Teacher:"] {
            if let range = description.range(of: prefix, options: .caseInsensitive) {
                let suffix = description[range.upperBound...]
                return String(suffix.prefix { !$0.isNewline }).trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }
}
