import Foundation
import CoreGraphics
import PDFKit
import UIKit
import Vision

enum ScheduleImportFormat: String, CaseIterable, Identifiable {
    case csv = "CSV"
    case json = "JSON"
    case ics = "ICS"
    case text = "复制文本"
    case html = "网页表格"
    case pdf = "PDF"
    case portal = "教务网页"

    var id: String { rawValue }
}

struct ScheduleImportPreview {
    let sourceName: String
    let format: ScheduleImportFormat
    let courses: [Course]
    let warnings: [String]

    // The preview uses the target timetable's timezone and bell times, including every slot.
    func timetablePreviewDate(reference: Date = .now, semesterStart: Date,
                              calendar: Calendar = .current) -> Date {
        let table = Timetable(semesterStartDate: semesterStart, timeZoneIdentifier: calendar.timeZone.identifier,
            courses: courses)
        return timetablePreviewDate(reference: reference, in: table)
    }

    func timetablePreviewDate(reference: Date = .now, in timetable: Timetable) -> Date {
        var table = timetable
        table.courses = courses
        let lastWeek = courses.flatMap(\.timeSlots).map { $0.activeWeeks?.max() ?? $0.resolvedEndWeek }.max() ?? 1
        table.weekCount = min(30, max(table.weekCount, lastWeek))
        let calendar = table.calendar
        let monday = Weekday.monday.date(inWeekContaining: reference, calendar: calendar)
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: monday) else { continue }
            if !ScheduleEngine.occurrences(in: table, on: day).isEmpty { return reference }
        }
        let semesterMonday = Weekday.monday.date(inWeekContaining: table.semesterStartDate, calendar: calendar)
        var candidates = courses.flatMap(\.timeSlots).flatMap { ($0.datedEvents ?? []).map(\.startDate) }
        candidates += courses.flatMap(\.exceptions).compactMap(\.startDate)
        for course in courses {
            for slot in course.timeSlots where slot.datedEvents == nil {
                for week in 1...table.weekCount where slot.isActive(academicWeek: week) {
                    for day in slot.weekdays {
                        if let date = calendar.date(byAdding: .day, value: (week - 1) * 7 + day.weekIndex, to: semesterMonday) {
                            candidates.append(date)
                        }
                    }
                }
            }
        }
        return candidates.sorted().first { !ScheduleEngine.occurrences(in: table, on: $0).isEmpty } ?? reference
    }

}

enum ScheduleImportError: LocalizedError {
    case unreadableFile
    case unsupportedFormat
    case emptyResult
    case malformed(String)

    var errorDescription: String? {
        switch self {
        case .unreadableFile: "无法读取所选文件。"
        case .unsupportedFormat: "暂不支持这种文件格式，请选择 PDF、CSV、JSON、ICS、HTML、TXT 或网页格式 XLS。"
        case .emptyResult: "文件中没有找到可导入的课程。"
        case .malformed(let detail): "文件内容无法识别：\(detail)"
        }
    }
}

enum ScheduleImportService {
    static func parseSchoolText(_ text: String, sourceName: String = "教务系统") throws -> ScheduleImportPreview {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        if normalized.range(of: #"<\s*(table|tr|td|th)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return try parseHTML(normalized, sourceName: sourceName)
        }

        let nonemptyLines = normalized.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let separator: Character? = nonemptyLines.first?.contains("\t") == true ? "\t" : (nonemptyLines.first?.contains(",") == true ? "," : nil)
        let result: ([Course], [String])
        if let separator {
            let rows = separator == "," ? parseCSVRows(normalized) : nonemptyLines.map { $0.split(separator: separator, omittingEmptySubsequences: false).map(String.init) }
            result = courses(fromTabularRows: rows)
        } else {
            result = courses(fromKeyValueText: normalized)
        }
        let courses = result.0
        let warnings = result.1
        guard !courses.isEmpty else { throw ScheduleImportError.emptyResult }
        return ScheduleImportPreview(sourceName: sourceName, format: .text, courses: courses, warnings: warnings)
    }

    static func parseHTML(_ html: String, sourceName: String = "教务网页") throws -> ScheduleImportPreview {
        var text = html
        let replacements = [
            (#"(?i)</\s*tr\s*>"#, "\n"),
            (#"(?i)</\s*(td|th)\s*>"#, "\t"),
            (#"(?i)<\s*br\s*/?\s*>"#, "\n"),
            (#"(?i)<[^>]+>"#, "")
        ]
        for (pattern, replacement) in replacements {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        var preview = try parseSchoolText(text, sourceName: sourceName)
        preview = ScheduleImportPreview(sourceName: preview.sourceName, format: .html, courses: preview.courses, warnings: preview.warnings)
        return preview
    }

    static func parseSchoolPortalPayload(_ payload: String, sourceName: String = "学校教务系统") throws -> ScheduleImportPreview {
        if payload.hasPrefix("__KEBIAO_GRID__") {
            let data = Data(payload.dropFirst("__KEBIAO_GRID__".count).utf8)
            let cells = try JSONDecoder().decode([TimetableGridCell].self, from: data)
            return try parseTimetableGrid(cells, sourceName: sourceName, format: .portal)
        }
        let parsed: ScheduleImportPreview
        if payload.range(of: #"<\s*(table|tr|td|th)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            parsed = try parseHTML(payload, sourceName: sourceName)
        } else {
            parsed = try parseSchoolText(payload, sourceName: sourceName)
        }
        return ScheduleImportPreview(
            sourceName: parsed.sourceName,
            format: .portal,
            courses: parsed.courses,
            warnings: parsed.warnings
        )
    }

    struct TimetableGridCell: Codable {
        let weekday: String
        let section: String
        let text: String
    }

    // Convert positioned browser cells without inferring a weekday from names.
    static func parseTimetableGrid(_ cells: [TimetableGridCell], sourceName: String,
                                   format: ScheduleImportFormat) throws -> ScheduleImportPreview {
        var courses: [Course] = []
        var warnings: [String] = []
        for cell in cells {
            let blocks = cell.text.replacingOccurrences(of: "\r\n", with: "\n")
                .components(separatedBy: "\n\n")
            for block in blocks where !block.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let lines = block.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                guard let first = lines.first else { continue }
                let name = first.replacingOccurrences(of: #"^(课程名称|课程名|课程)\s*[:：]\s*"#,
                                                      with: "", options: .regularExpression)
                let schedule = lines.dropFirst().joined(separator: " ")
                guard let sections = sectionRange(schedule) ?? explicitSectionRange(cell.section),
                      (1...12).contains(sections.0), (sections.0...12).contains(sections.1) else {
                    warnings.append("「\(name)」的节次不明确，已跳过，请核对原课表")
                    continue
                }
                var record = ["课程名称": name, "星期": cell.weekday,
                              "节次": "\(sections.0)-\(sections.1)", "上课时间": schedule]
                // Explicit section text is more precise than a vertically merged cell.
                for line in lines.dropFirst() {
                    if let colon = line.firstIndex(where: { $0 == ":" || $0 == "：" }) {
                        let key = normalizedKey(String(line[..<colon]))
                        let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                        if ["教师", "任课教师", "老师", "地点", "上课地点", "教室", "周次", "周数", "上课周数"].contains(key) {
                            record[key == "周次" ? "上课周数" : key] = value
                        }
                    }
                }
                guard let parsed = course(from: record) else {
                    warnings.append("「\(name)」缺少明确的星期或节次，已跳过，请核对原课表")
                    continue
                }
                courses.append(parsed)
                if parsed.activeWeeks == nil {
                    warnings.append("「\(name)」的周次未识别，请核对后导入")
                }
            }
        }
        guard !courses.isEmpty else { throw ScheduleImportError.emptyResult }
        return ScheduleImportPreview(sourceName: sourceName, format: format, courses: courses, warnings: warnings)
    }

    static func parsePDF(data: Data, sourceName: String = "课表.pdf") throws -> ScheduleImportPreview {
        guard let document = PDFDocument(data: data) else {
            throw ScheduleImportError.malformed("PDF 文件已损坏或受密码保护")
        }

        // Some school exports use predefined UCS2 CMaps without a ToUnicode
        // table. Decode their declared Unicode strings before OCR can lose the
        // row-spanned weekday/section labels in a dense, rotated table.
        if let exact = parseUnicodeSchoolRows(unicodePDFPages(document), sourceName: sourceName) {
            return exact
        }

        let embeddedText = document.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if embeddedText.filter({ $0 == "\u{FFFD}" }).count <= 3,
           let parsed = parsedPDFText(embeddedText, sourceName: sourceName) {
            return parsed
        }

        let grid = recognizePDFPages(document)
        if !grid.0.isEmpty {
            return ScheduleImportPreview(
                sourceName: sourceName,
                format: .pdf,
                courses: grid.0,
                warnings: ["已使用图像识别，请核对课程名、星期、节次和周次"] + grid.1
            )
        }

        let recognized = try recognizedText(in: document)
        if let parsed = parsedPDFText(recognized, sourceName: sourceName) {
            return parsed
        }
        throw ScheduleImportError.emptyResult
    }

    private static func unicodePDFPages(_ document: PDFDocument) -> [[String]] {
        (0..<document.pageCount).map { index in
            guard let page = document.page(at: index)?.pageRef,
                  let table = CGPDFOperatorTableCreate() else { return [] }
            var resources: CGPDFDictionaryRef?
            var fonts: CGPDFDictionaryRef?
            if let dictionary = page.dictionary,
               CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources {
                _ = CGPDFDictionaryGetDictionary(resources, "Font", &fonts)
            }
            let collector = PDFUnicodeTextCollector(fonts: fonts)
            CGPDFOperatorTableSetCallback(table, "Tf", PDFUnicodeTextCollector.selectFont)
            CGPDFOperatorTableSetCallback(table, "Tj", PDFUnicodeTextCollector.showText)
            CGPDFOperatorTableSetCallback(table, "TJ", PDFUnicodeTextCollector.showTextArray)
            let stream = CGPDFContentStreamCreateWithPage(page)
            let scanner = CGPDFScannerCreate(stream, table, Unmanaged.passUnretained(collector).toOpaque())
            guard CGPDFScannerScan(scanner) else { return [] }
            return collector.lines
        }
    }

    static func parseUnicodeSchoolRows(_ pages: [[String]], sourceName: String) -> ScheduleImportPreview? {
        var day: Weekday?
        var sections: (Int, Int)?
        var name: String?
        var details: [String] = []
        var courses: [Course] = []
        var warnings: [String] = []
        var expectedRows = 0

        func flush() {
            guard let title = name else { return }
            defer { name = nil; details = [] }
            let detail = details.joined(separator: " ")
            guard let day, let sections, detail.contains("周数") else { return }
            let weekText = pdfField("周数", in: detail)
            let weeks = pdfWeekNumbers(weekText)
            guard !weeks.isEmpty else { return }
            courses.append(Course(name: title, teacher: pdfField("教师", in: detail),
                location: pdfField("地点", in: detail), startSection: min(12, max(1, sections.0)),
                sectionCount: min(13 - min(12, max(1, sections.0)), sections.1 - sections.0 + 1), weekdays: [day],
                colorValue: palette[title.utf8.reduce(0) { ($0 + Int($1)) % palette.count }],
                startTimeMinutes: nil, reminderMinutesBefore: 10,
                startWeek: weeks.min(), endWeek: weeks.max(), activeWeeks: weeks,
                notes: "原始周次：\(weekText)"))
        }

        for page in pages {
            var pendingDayHeader = false
            for raw in page {
                let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.range(of: #"^(星期|周)[一二三四五六日天]$"#, options: .regularExpression) != nil,
                   let weekday = parseWeekdays(line).first {
                    // Consecutive weekday headers describe a column grid,
                    // rather than the row-grouped school export handled here.
                    if pendingDayHeader { return nil }
                    flush()
                    day = weekday
                    sections = nil
                    pendingDayHeader = true
                } else if let range = pdfSectionRange(line) {
                    flush()
                    sections = range
                    pendingDayHeader = false
                } else if line.hasPrefix("实践课程") {
                    flush()
                    warnings.append("PDF 包含未指定星期和节次的实践课程，请按学校安排手动添加")
                } else if let last = line.last, "★☆◆◇■●".contains(last),
                          let title = pdfCourseName(line) {
                    flush()
                    expectedRows += 1
                    name = title
                } else if name != nil {
                    details.append(line)
                }
            }
            flush()
            // The next page can continue a merged weekday cell. Keep the day,
            // but require an explicit new section label before adding a course.
            sections = nil
        }
        // A partial decode must not silently bypass the generic/OCR paths.
        guard !courses.isEmpty, courses.count == expectedRows else { return nil }
        return ScheduleImportPreview(sourceName: sourceName, format: .pdf, courses: courses, warnings: warnings)
    }

    private static func parsedPDFText(_ text: String, sourceName: String) -> ScheduleImportPreview? {
        guard !text.isEmpty else { return nil }
        if let parsed = try? parseSchoolText(text, sourceName: sourceName) {
            return ScheduleImportPreview(
                sourceName: sourceName, format: .pdf, courses: parsed.courses, warnings: parsed.warnings
            )
        }
        let reconstructed = courses(fromSeparatedPDFText: text)
        let result = reconstructed.0.isEmpty ? courses(fromLoosePDFText: text) : reconstructed
        guard !result.0.isEmpty else { return nil }
        return ScheduleImportPreview(sourceName: sourceName, format: .pdf, courses: result.0, warnings: result.1)
    }

    private struct PDFOCRLine {
        let text: String
        let y: CGFloat // Distance from the top of the rendered page, from 0 to 1.
    }

    private static func recognizePDFPages(_ document: PDFDocument) -> ([Course], [String]) {
        var courses: [Course] = []
        var warnings: [String] = []
        var previousDay: Weekday?

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let size = CGSize(width: bounds.width * 3, height: bounds.height * 3)
            guard let image = page.thumbnail(of: size, for: .mediaBox).cgImage else { continue }

            let dayLines = recognizePDFText(in: image, x: 0.018...0.095)
                .compactMap { line -> (PDFOCRLine, Weekday)? in
                    guard line.text.contains("周") || line.text.contains("星期"),
                          let day = parseWeekdays(line.text).first else { return nil }
                    return (line, day)
                }
            let sectionLines = recognizePDFText(in: image, x: 0.075...0.175)
                .compactMap { line -> (PDFOCRLine, (Int, Int))? in
                    guard let section = pdfSectionRange(line.text) else { return nil }
                    return (line, section)
                }
            let nameLines = recognizePDFText(in: image, x: 0.16...0.415)
                .filter { pdfCourseName($0.text) != nil }
                .sorted { $0.y < $1.y }
            let detailLines = recognizePDFText(in: image, x: 0.415...0.985)
            let rawBoundaries = pdfDayBoundaries(in: image)
            let flippedBoundaries = rawBoundaries.map { 1 - $0 }.sorted()
            func labeledRows(_ boundaries: [CGFloat]) -> Int {
                nameLines.filter { name in
                    dayLines.contains { pdfBand(at: $0.0.y, boundaries: boundaries) == pdfBand(at: name.y, boundaries: boundaries) }
                }.count
            }
            let boundaries = labeledRows(flippedBoundaries) > labeledRows(rawBoundaries) ? flippedBoundaries : rawBoundaries

            let previousCourseCount = courses.count
            for nameLine in nameLines {
                let band = pdfBand(at: nameLine.y, boundaries: boundaries)
                let sameBandNames = nameLines.filter { pdfBand(at: $0.y, boundaries: boundaries) == band }
                let position = sameBandNames.firstIndex { $0.y == nameLine.y && $0.text == nameLine.text } ?? 0
                let lower = position == 0 ? boundaries[band] : (sameBandNames[position - 1].y + nameLine.y) / 2
                let upper = position + 1 == sameBandNames.count ? boundaries[band + 1] : (nameLine.y + sameBandNames[position + 1].y) / 2
                let details = detailLines
                    .filter { $0.y >= lower && $0.y < upper }
                    .sorted { $0.y < $1.y }
                    .map(\.text)
                    .joined(separator: " ")
                let day = (boundaries.count > 2 ? dayLines.first { pdfBand(at: $0.0.y, boundaries: boundaries) == band }?.1 : nil)
                    ?? dayLines.min { abs($0.0.y - nameLine.y) < abs($1.0.y - nameLine.y) }?.1
                    ?? previousDay
                let sections = sectionLines
                    .filter { pdfBand(at: $0.0.y, boundaries: boundaries) == band }
                    .min { abs($0.0.y - nameLine.y) < abs($1.0.y - nameLine.y) }?.1

                guard let day, let sections, let name = pdfCourseName(nameLine.text) else { continue }
                let weekText = pdfField("周数", in: details)
                let weeks = pdfWeekNumbers(weekText)
                let teacher = pdfField("教师", in: details)
                let location = pdfField("地点", in: details)
                let colorIndex = name.utf8.reduce(0) { ($0 + Int($1)) % palette.count }
                courses.append(Course(
                    name: name,
                    teacher: teacher,
                    location: location,
                    startSection: min(12, max(1, sections.0)),
                    sectionCount: min(13 - min(12, max(1, sections.0)), max(1, sections.1 - sections.0 + 1)),
                    weekdays: [day],
                    colorValue: palette[colorIndex],
                    startTimeMinutes: nil,
                    reminderMinutesBefore: 10,
                    startWeek: weeks.min(),
                    endWeek: weeks.max(),
                    activeWeeks: weeks.isEmpty ? nil : weeks,
                    notes: weekText.isEmpty ? nil : "原始周次：\(weekText)"
                ))
                if weeks.isEmpty {
                    warnings.append("第 \(pageIndex + 1) 页「\(name)」的周次未识别，请在导入后核对")
                }
            }
            previousDay = dayLines.sorted { $0.0.y < $1.0.y }.last?.1 ?? previousDay

            if courses.count == previousCourseCount {
                // A scanned PDF without a timetable grid may still contain line-based records.
                let lines = recognizePDFText(in: image, x: 0.02...0.98)
                    .sorted { $0.y < $1.y }
                    .map(\.text)
                    .joined(separator: "\n")
                if let preview = try? parseSchoolText(lines) {
                    courses.append(contentsOf: preview.courses)
                    warnings.append(contentsOf: preview.warnings)
                } else {
                    let loose = Self.courses(fromLoosePDFText: lines)
                    courses.append(contentsOf: loose.0)
                    warnings.append(contentsOf: loose.1)
                }
            }
        }
        return (courses, warnings)
    }

    private static func recognizePDFText(in image: CGImage, x: ClosedRange<CGFloat>) -> [PDFOCRLine] {
        let left = max(0, Int(CGFloat(image.width) * x.lowerBound))
        let right = min(image.width, Int(CGFloat(image.width) * x.upperBound))
        guard right > left,
              let crop = image.cropping(to: CGRect(x: CGFloat(left), y: 0, width: CGFloat(right - left), height: CGFloat(image.height))) else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.003
        let handler = VNImageRequestHandler(cgImage: crop, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return PDFOCRLine(text: candidate.string, y: 1 - observation.boundingBox.midY)
        }
    }

    private static func pdfDayBoundaries(in image: CGImage) -> [CGFloat] {
        guard image.bitsPerComponent == 8, image.bitsPerPixel >= 24,
              let provider = image.dataProvider?.data,
              CFDataGetLength(provider) >= image.bytesPerRow * image.height,
              let bytes = CFDataGetBytePtr(provider) else { return [0, 1] }
        let pixelSize = image.bitsPerPixel / 8
        let left = Int(CGFloat(image.width) * 0.027)
        let right = Int(CGFloat(image.width) * 0.072)
        guard right > left else { return [0, 1] }
        var rules: [CGFloat] = []
        for y in 0..<image.height {
            var dark = 0
            var checked = 0
            for x in stride(from: left, to: right, by: 3) {
                let offset = y * image.bytesPerRow + x * pixelSize
                let brightness = Int(bytes[offset]) + Int(bytes[offset + 1]) + Int(bytes[offset + 2])
                if brightness < 370 { dark += 1 }
                checked += 1
            }
            if checked > 0 && dark * 10 >= checked * 8 {
                let normalized = CGFloat(y) / CGFloat(image.height)
                if let last = rules.last, normalized - last < 0.005 {
                    rules[rules.count - 1] = (last + normalized) / 2
                } else {
                    rules.append(normalized)
                }
            }
        }
        return ([0] + rules.filter { $0 > 0.01 && $0 < 0.99 } + [1]).sorted()
    }

    private static func pdfBand(at y: CGFloat, boundaries: [CGFloat]) -> Int {
        max(0, min(boundaries.count - 2, (boundaries.lastIndex(where: { $0 <= y }) ?? 0)))
    }

    private static func pdfSectionRange(_ text: String) -> (Int, Int)? {
        guard let values = capturedIntegers(
            in: text,
            pattern: #"^\s*第?\s*(\d{1,2})\s*[-–—~至到]\s*(\d{1,2})\s*节?\s*$"#
        ), values.count == 2, (1...12).contains(values[0]), (values[0]...12).contains(values[1]) else { return nil }
        return (values[0], values[1])
    }

    private static func pdfCourseName(_ text: String) -> String? {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "★☆◆◇■●·"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count >= 2, name.count <= 45,
              !name.contains("课表"), !name.contains("学号"),
              !name.contains("周数"), !name.contains("校区"),
              !name.contains("教师:"), !name.contains("教师：") else { return nil }
        return name
    }

    static func pdfField(_ key: String, in text: String) -> String {
        let nextField = #"(?:周数|周次|地点|教师|校区|教学班|教学组成|课程学时|总学时|学分|考核方式|备注)"#
        let pattern = NSRegularExpression.escapedPattern(for: key)
            + #"\s*[:：]\s*(.*?)(?=[/／|｜]|\s*"# + nextField + #"\s*[:：]|$)"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return "" }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func pdfWeekNumbers(_ text: String) -> Set<Int> {
        var weeks = Set<Int>()
        for part in text.replacingOccurrences(of: "，", with: ",").split(separator: ",") {
            let segment = String(part)
            let numbers = segment.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
            guard let first = numbers.first, (1...30).contains(first) else { continue }
            let last = min(30, max(first, numbers.dropFirst().first ?? first))
            let oddOnly = segment.contains("单")
            let evenOnly = segment.contains("双")
            for week in first...last where (!oddOnly || week % 2 == 1) && (!evenOnly || week % 2 == 0) {
                weeks.insert(week)
            }
        }
        return weeks
    }

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
        case "pdf":
            return try parsePDF(data: data, sourceName: url.lastPathComponent)
        case "csv":
            format = .csv
            result = try parseCSV(data)
        case "json":
            format = .json
            result = try parseJSON(data)
        case "ics", "ical":
            format = .ics
            result = try parseICS(data)
        case "html", "htm":
            guard let text = decodedText(data) else { throw ScheduleImportError.malformed("无法识别网页文字编码") }
            return try parseHTML(text, sourceName: url.lastPathComponent)
        case "txt", "tsv", "xls":
            guard let text = decodedText(data) else { throw ScheduleImportError.malformed("无法识别文字编码") }
            return try parseSchoolText(text, sourceName: url.lastPathComponent)
        case "xlsx":
            throw ScheduleImportError.malformed("XLSX 请先在教务系统中另存为 CSV，或复制表格后使用粘贴导入")
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
        guard let text = decodedText(data) else { throw ScheduleImportError.malformed("无法识别文字编码") }
        let rows = parseCSVRows(text)
        guard let header = rows.first, header.count > 1 else { throw ScheduleImportError.malformed("缺少表头") }
        return courses(fromTabularRows: rows)
    }

    private static func courses(fromTabularRows rows: [[String]]) -> ([Course], [String]) {
        var keys: [String] = []
        func isCourseHeader(_ row: [String]) -> Bool {
            row.map(normalizedKey).contains { ["coursename", "course", "name", "课程名称", "课程名", "课程", "科目"].contains($0) }
        }
        var courses: [Course] = []
        var warnings: [String] = []
        for (offset, row) in rows.enumerated() where row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            if isCourseHeader(row) { keys = row.map(normalizedKey); continue }
            guard !keys.isEmpty else { continue }
            var record: [String: String] = [:]
            for index in keys.indices where index < row.count {
                record[keys[index]] = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let course = course(from: record) {
                courses.append(course)
            } else {
                warnings.append("第 \(offset + 2) 行无法识别，已跳过")
            }
        }
        return (courses, warnings)
    }

    private static func courses(fromKeyValueText text: String) -> ([Course], [String]) {
        let blocks = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: #"(?m)^\s*$"#, with: "\u{001E}", options: .regularExpression)
            .components(separatedBy: "\u{001E}")
        var courses: [Course] = []
        var warnings: [String] = []
        for (offset, block) in blocks.enumerated() {
            var record: [String: String] = [:]
            for line in block.components(separatedBy: .newlines) {
                guard let separator = line.firstIndex(where: { $0 == ":" || $0 == "：" }) else { continue }
                let key = String(line[..<separator])
                let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { record[normalizedKey(key)] = value }
            }
            if let course = course(from: record) {
                courses.append(course)
            } else if !record.isEmpty {
                warnings.append("第 \(offset + 1) 段无法识别，已跳过")
            }
        }
        return (courses, warnings)
    }

    private static func courses(fromLoosePDFText text: String) -> ([Course], [String]) {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var courses: [Course] = []
        var warnings: [String] = []

        for (index, line) in lines.enumerated() {
            let weekdays = parseWeekdays(line)
            guard !weekdays.isEmpty, let sections = sectionRange(line) else { continue }

            let tokens = line
                .replacingOccurrences(of: #"\s{2,}"#, with: "\t", options: .regularExpression)
                .components(separatedBy: CharacterSet(charactersIn: "\t|｜,，;；"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let name = tokens.first(where: {
                !$0.contains("周") && !$0.contains("星期") && sectionRange($0) == nil &&
                !$0.contains("课程名称") && !$0.contains("任课教师") && !$0.contains("上课地点")
            }) ?? ""
            guard name.count >= 2 else {
                warnings.append("PDF 第 \(index + 1) 行缺少可识别的课程名称，已跳过")
                continue
            }

            let teacher = tokens.first(where: { $0.contains("老师") || $0.contains("教师") || $0.contains("教授") }) ?? ""
            let location = tokens.first(where: {
                $0 != name && ($0.contains("楼") || $0.contains("室") || $0.contains("馆") || $0.contains("场"))
            }) ?? ""
            let weeks = academicWeeks(line, explicitField: false)
            let colorIndex = name.utf8.reduce(0) { ($0 + Int($1)) % palette.count }
            courses.append(Course(
                name: name,
                teacher: teacher,
                location: location,
                startSection: min(12, max(1, sections.0)),
                sectionCount: min(13 - min(12, max(1, sections.0)), max(1, sections.1 - sections.0 + 1)),
                weekdays: weekdays,
                colorValue: palette[colorIndex],
                startTimeMinutes: nil,
                reminderMinutesBefore: 10,
                startWeek: weeks?.min(),
                endWeek: weeks?.max(),
                activeWeeks: weeks
            ))
        }
        return (courses, warnings)
    }

    private static func courses(fromSeparatedPDFText text: String) -> ([Course], [String]) {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var courses: [Course] = []
        var warnings: [String] = []
        var record: [String: String] = [:]
        var pendingKey: String?

        func flushRecord() {
            guard !record.isEmpty else { return }
            if let parsed = course(from: record) {
                courses.append(parsed)
            } else if record["课程名称"] != nil {
                warnings.append("PDF 中有一门课程缺少可识别的星期或节次，已跳过")
            }
            record.removeAll(keepingCapacity: true)
            pendingKey = nil
        }

        for line in lines {
            if let key = pdfFieldKey(line) {
                if key == "课程名称", record["课程名称"] != nil {
                    flushRecord()
                }
                pendingKey = key
                continue
            }

            if let key = pendingKey {
                record[key] = line
                pendingKey = nil
                continue
            }

            guard record["课程名称"] != nil else { continue }
            if !parseWeekdays(line).isEmpty || sectionRange(line) != nil || containsExplicitWeekRange(line) {
                let current = record["上课时间", default: ""]
                record["上课时间"] = [current, line].filter { !$0.isEmpty }.joined(separator: " ")
            }
        }
        flushRecord()
        return (courses, warnings)
    }

    private static func pdfFieldKey(_ line: String) -> String? {
        let key = normalizedKey(
            line.trimmingCharacters(in: CharacterSet(charactersIn: ":："))
        )
        switch key {
        case "课程名称", "课程名", "课程", "科目": return "课程名称"
        case "任课教师", "任课老师", "教师", "老师": return "任课教师"
        case "上课地点", "教学地点", "地点", "教室": return "上课地点"
        case "上课时间", "课程安排", "上课安排", "时间地点": return "上课时间"
        case "星期", "星期几", "周几": return "星期"
        case "节次", "开始节次", "开始节数": return "节次"
        case "上课周数", "周数", "周次": return "上课周数"
        default: return nil
        }
    }

    private static func containsExplicitWeekRange(_ text: String) -> Bool {
        text.range(of: #"\d+\s*[-–—~至到]\s*\d+\s*周"#, options: .regularExpression) != nil
    }

    private static func recognizedText(in document: PDFDocument) throws -> String {
        var pages: [String] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let image = page.thumbnail(of: CGSize(width: 2000, height: 2800), for: .mediaBox)
            guard let cgImage = image.cgImage else { continue }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            if let supported = try? request.supportedRecognitionLanguages() {
                let preferred = ["zh-Hans", "en-US"].filter(supported.contains)
                if !preferred.isEmpty { request.recognitionLanguages = preferred }
            }

            do {
                try VNImageRequestHandler(cgImage: cgImage).perform([request])
            } catch {
                throw ScheduleImportError.malformed("扫描 PDF 文字识别失败：\(error.localizedDescription)")
            }

            let observations = (request.results ?? []).sorted { lhs, rhs in
                if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > 0.015 {
                    return lhs.boundingBox.midY > rhs.boundingBox.midY
                }
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }
            let lines = observations.compactMap { $0.topCandidates(1).first?.string }
            if !lines.isEmpty { pages.append(lines.joined(separator: "\n")) }
        }

        let text = normalizedOCRText(pages.joined(separator: "\n"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw ScheduleImportError.malformed("扫描 PDF 中没有识别到课表文字，请换用更清晰、方向正确的文件")
        }
        return text
    }

    private static func normalizedOCRText(_ text: String) -> String {
        let aliases: [(String, String)] = [
            ("course name", "course"), ("course", "course"),
            ("teacher", "teacher"), ("location", "location"),
            ("weekday", "weekday"), ("section", "section"), ("weeks", "weeks"),
            ("课程名称", "课程名称"), ("课程名", "课程名称"),
            ("任课教师", "任课教师"), ("任课老师", "任课教师"),
            ("上课地点", "上课地点"), ("教学地点", "上课地点"),
            ("上课时间", "上课时间"), ("课程安排", "上课时间"),
            ("星期", "星期"), ("节次", "节次"), ("周数", "上课周数")
        ]
        let separatorCharacters = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ":：;；|｜-—"))
        return text.components(separatedBy: .newlines).map { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            for (alias, canonical) in aliases {
                guard let range = trimmed.range(of: alias, options: [.anchored, .caseInsensitive]) else { continue }
                let value = trimmed[range.upperBound...].trimmingCharacters(in: separatorCharacters)
                if !value.isEmpty { return "\(canonical): \(value)" }
            }
            return trimmed
        }.joined(separator: "\n")
    }

    private static func decodedText(_ data: Data) -> String? {
        let gb18030 = String.Encoding(rawValue: 0x80000632)
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: gb18030)
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
            if object["timeSlots"] != nil || (object["id"] != nil && object["colorValue"] != nil) {
                var native = object
                if let slots = object["timeSlots"] as? [[String: Any]] {
                    guard !slots.isEmpty else {
                        warnings.append("第 \(index + 1) 条没有上课时段，已跳过")
                        continue
                    }
                    native["id"] = native["id"] ?? UUID().uuidString
                    native["colorValue"] = native["colorValue"] ?? palette[index % palette.count]
                    native["timeSlots"] = slots.map { value -> [String: Any] in
                        var slot = value
                        let defaults: [String: Any] = ["id": UUID().uuidString, "teacher": "", "location": "",
                            "startSection": 1, "sectionCount": 2, "weekdays": [Weekday.monday.rawValue]]
                        for (key, value) in defaults where slot[key] == nil { slot[key] = value }
                        if let events = slot["datedEvents"] as? [[String: Any]] {
                            slot["datedEvents"] = events.map { value -> [String: Any] in
                                var event = value
                                event["id"] = event["id"] ?? UUID().uuidString
                                return event
                            }
                        }
                        return slot
                    }
                }
                guard let data = try? JSONSerialization.data(withJSONObject: native),
                      var course = try? JSONDecoder().decode(Course.self, from: data) else {
                    warnings.append("第 \(index + 1) 条原生课程数据无效，已跳过")
                    continue
                }
                course.normalize()
                guard (try? course.validate()) != nil else {
                    warnings.append("第 \(index + 1) 条原生课程安排无效，已跳过")
                    continue
                }
                courses.append(course)
                continue
            }

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
        let unfolded = raw.replacingOccurrences(of: "\r\n ", with: "").replacingOccurrences(of: "\r\n\t", with: "")
            .replacingOccurrences(of: "\n ", with: "").replacingOccurrences(of: "\n\t", with: "")
        var courses: [Course] = []
        var warnings: [String] = []
        for (index, block) in unfolded.components(separatedBy: "BEGIN:VEVENT").dropFirst().enumerated() {
            let lines = (block.components(separatedBy: "END:VEVENT").first ?? block).components(separatedBy: .newlines)
            if icsValue("STATUS", in: lines).uppercased() == "CANCELLED" { continue }
            do {
                guard icsValue("RECURRENCE-ID", in: lines).isEmpty else {
                    throw ScheduleImportError.malformed("暂不支持改期事件，请导出不含 RECURRENCE-ID 的课表")
                }
                let name = icsValue("SUMMARY", in: lines)
                guard !name.isEmpty, let start = icsDate("DTSTART", in: lines),
                      let startLine = lines.first(where: { $0.uppercased().hasPrefix("DTSTART") }),
                      icsValue("DTSTART", in: lines).contains("T") else {
                    throw ScheduleImportError.malformed("缺少课程名称或带具体时间的 DTSTART，不支持全天课程")
                }
                let end = icsDate("DTEND", in: lines) ?? start.addingTimeInterval(50 * 60)
                guard end > start, end.timeIntervalSince(start) <= 86_400 else {
                    throw ScheduleImportError.malformed("课程时长必须在 1 分钟到 24 小时之间")
                }
                let starts = try icsOccurrences(lines: lines, start: start, startLine: startLine, warnings: &warnings)
                // Group by local clock time so DST conversions still display the correct time.
                let groups = Dictionary(grouping: starts) {
                    Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0)
                }
                let description = icsValue("DESCRIPTION", in: lines)
                let duration = max(1, Int(end.timeIntervalSince(start) / 60))
                for minutes in groups.keys.sorted() {
                    let dates = Set(groups[minutes] ?? [])
                    guard !dates.isEmpty else { continue }
                    let section = nearestSection(to: minutes)
                    let count = min(13 - section, max(1, Int(round(Double(duration) / 55))))
                    courses.append(Course(
                        name: name, teacher: teacher(from: description), location: icsValue("LOCATION", in: lines),
                        startSection: section, sectionCount: count,
                        weekdays: Set(dates.map { Weekday.from(calendarWeekday: Calendar.current.component(.weekday, from: $0)) }),
                        colorValue: palette[courses.count % palette.count], startTimeMinutes: minutes, reminderMinutesBefore: 10,
                        notes: description.isEmpty ? nil : description, scheduledDates: dates, durationMinutes: duration
                    ))
                }
            } catch {
                warnings.append("第 \(index + 1) 个日历事件已跳过：\(error.localizedDescription)")
            }
        }
        return (courses, warnings)
    }

    private static func icsOccurrences(lines: [String], start: Date, startLine: String, warnings: inout [String]) throws -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        if icsValue("DTSTART", in: lines).hasSuffix("Z") { calendar.timeZone = TimeZone(secondsFromGMT: 0)! }
        else { calendar.timeZone = try icsTimeZone(header: startLine) }
        calendar.firstWeekday = 2
        let ruleText = icsValue("RRULE", in: lines).uppercased()
        var dates: Set<Date> = [start]
        if !ruleText.isEmpty {
            var rule: [String: String] = [:]
            for part in ruleText.split(separator: ";") {
                let fields = part.split(separator: "=", maxSplits: 1).map(String.init)
                if fields.count == 2 { rule[fields[0]] = fields[1] }
            }
            guard let frequency = rule["FREQ"], ["WEEKLY", "DAILY"].contains(frequency),
                  Set(rule.keys).isSubset(of: ["FREQ", "INTERVAL", "BYDAY", "COUNT", "UNTIL", "WKST"]),
                  rule["WKST"] == nil || rule["WKST"] == "MO" else {
                throw ScheduleImportError.malformed("仅支持按日/周重复及 MO 周起点，复杂规则请转为具体日期")
            }
            let interval = Int(rule["INTERVAL"] ?? "1") ?? 0
            let count = rule["COUNT"].flatMap(Int.init)
            guard (1...365).contains(interval), rule["COUNT"] == nil || (count ?? 0) > 0,
                  rule["COUNT"] == nil || rule["UNTIL"] == nil else {
                throw ScheduleImportError.malformed("重复次数或间隔无效")
            }
            let until = rule["UNTIL"].flatMap { parseICSDate($0, header: startLine) }
            if rule["UNTIL"] != nil && (until == nil || until! < start) { throw ScheduleImportError.malformed("重复结束日期无效或早于开始时间") }
            let mapping = ["MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7, "SU": 1]
            let codes = rule["BYDAY"]?.split(separator: ",").map(String.init) ?? []
            guard codes.allSatisfy({ mapping[$0] != nil }) else { throw ScheduleImportError.malformed("暂不支持带序号的 BYDAY") }
            let days = codes.isEmpty ? Set([calendar.component(.weekday, from: start)]) : Set(codes.compactMap { mapping[$0] })
            let startDay = calendar.startOfDay(for: start)
            let startWeek = Weekday.monday.date(inWeekContaining: start, calendar: calendar)
            let parts = calendar.dateComponents([.hour, .minute, .second], from: start)
            let horizon = calendar.date(byAdding: .day, value: 730, to: start)!
            let bound = until.map { min($0, horizon) } ?? (count == nil ? calendar.date(byAdding: .day, value: 210, to: start)! : horizon)
            if count == nil && until == nil { warnings.append("无结束日期的重复课程只导入从开始日期起 30 周，请在下学期重新导入。") }
            for offset in 1...730 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: startDay),
                      let candidate = calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: parts.second ?? 0, of: day) else { continue }
                if candidate > bound || (count != nil && dates.count >= count!) { break }
                let week = Weekday.monday.date(inWeekContaining: candidate, calendar: calendar)
                let weekIndex = (calendar.dateComponents([.day], from: startWeek, to: week).day ?? 0) / 7
                let matches = frequency == "DAILY" ? offset % interval == 0 && (codes.isEmpty || days.contains(calendar.component(.weekday, from: candidate)))
                    : weekIndex % interval == 0 && days.contains(calendar.component(.weekday, from: candidate))
                if matches { dates.insert(candidate) }
            }
            // Include matching days later in the DTSTART week; the daily loop above already does this.
            if let count, dates.count < count { warnings.append("重复课程超过两年导入范围，仅保留范围内日期。") }
            if let until, until > horizon { warnings.append("重复课程结束日期超过两年，仅导入两年内日期。") }
        }
        for line in lines where line.uppercased().hasPrefix("RDATE") || line.uppercased().hasPrefix("EXDATE") {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let isExcluded = line.uppercased().hasPrefix("EXDATE")
            for value in line[line.index(after: separator)...].split(separator: ",") {
                guard let date = parseICSDate(String(value), header: line) else { throw ScheduleImportError.malformed("附加或排除日期无效") }
                if isExcluded { dates.remove(date) } else { dates.insert(date) }
            }
        }
        return dates.sorted()
    }

    private static func icsTimeZone(header: String) throws -> TimeZone {
        let parameters = header.components(separatedBy: ":").first?.components(separatedBy: ";") ?? []
        if let parameter = parameters.first(where: { $0.uppercased().hasPrefix("TZID=") }) {
            let identifier = String(parameter.dropFirst(5)).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            guard let zone = TimeZone(identifier: identifier) else { throw ScheduleImportError.malformed("无法识别时区 \(identifier)") }
            return zone
        }
        return .current
    }

    private static func parseICSDate(_ value: String, header: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.isLenient = false
        formatter.timeZone = value.hasSuffix("Z") ? TimeZone(secondsFromGMT: 0) : (try? icsTimeZone(header: header))
        if !value.hasSuffix("Z"), (try? icsTimeZone(header: header)) == nil { return nil }
        let format: String
        if value.range(of: #"^\d{8}T\d{6}Z$"#, options: .regularExpression) != nil { format = "yyyyMMdd'T'HHmmss'Z'" }
        else if value.range(of: #"^\d{8}T\d{6}$"#, options: .regularExpression) != nil { format = "yyyyMMdd'T'HHmmss" }
        else if value.range(of: #"^\d{8}T\d{4}$"#, options: .regularExpression) != nil { format = "yyyyMMdd'T'HHmm" }
        else if value.range(of: #"^\d{8}$"#, options: .regularExpression) != nil { format = "yyyyMMdd" }
        else { return nil }
        formatter.dateFormat = format
        return formatter.date(from: value)
    }

    private static let palette = [0xFF4B68, 0x29B8AF, 0x7B68C8, 0xF29F36, 0x438DDB, 0xE96A42]

    private static func course(from record: [String: String]) -> Course? {
        let name = value(in: record, keys: ["coursename", "course", "name", "课程名称", "课程名", "课程", "科目"])
        let scheduleText = value(in: record, keys: ["coursetime", "上课时间", "上课安排", "课程安排", "时间地点", "时间"])
        let dayText = value(in: record, keys: ["weekday", "weekdays", "day", "星期", "星期几", "周几"])
        let resolvedDayText = dayText.isEmpty ? scheduleText : dayText
        let weekdays = parseWeekdays(resolvedDayText)
        guard !name.isEmpty, !weekdays.isEmpty else { return nil }

        let sectionText = value(in: record, keys: ["startsection", "section", "period", "开始节次", "节次", "开始节数"])
        let parsedSections = sectionText.isEmpty ? sectionRange(scheduleText)
            : (sectionText.range(of: #"[-–—~至到节]"#, options: .regularExpression) != nil ? explicitSectionRange(sectionText) : nil)
        let section = parsedSections?.0 ?? intValue(sectionText) ?? 1
        let count = parsedSections.map { $0.1 - $0.0 + 1 } ?? intValue(value(in: record, keys: ["sectioncount", "duration", "节数", "连续节数"])) ?? 2
        let time = intValue(value(in: record, keys: ["starttimeminutes"])) ?? timeMinutes(value(in: record, keys: ["starttime", "time", "开始时间", "上课时间"]))
        let weekText = value(in: record, keys: ["weeks", "weekrange", "周数", "上课周数"])
        let explicitWeeks = value(in: record, keys: ["activeweeks"])
        let weekNumbers = academicWeeks(explicitWeeks.isEmpty ? (weekText.isEmpty ? scheduleText : weekText) : explicitWeeks,
                                        explicitField: !explicitWeeks.isEmpty || !weekText.isEmpty)
        let colorIndex = name.utf8.reduce(0) { ($0 + Int($1)) % palette.count }
        let color = Int(value(in: record, keys: ["colorvalue"])) ?? colorValue(value(in: record, keys: ["color", "颜色"])) ?? palette[colorIndex]
        return Course(
            name: name,
            teacher: value(in: record, keys: ["teacher", "instructor", "老师", "教师", "任课教师", "任课老师"]),
            location: value(in: record, keys: ["location", "classroom", "room", "教室", "地点", "上课地点", "教学地点"]),
            startSection: min(12, max(1, section)),
            sectionCount: min(13 - min(12, max(1, section)), max(1, count)),
            weekdays: weekdays,
            colorValue: color,
            startTimeMinutes: time,
            reminderMinutesBefore: intValue(value(in: record, keys: ["reminderminutesbefore", "reminder", "提醒", "提前提醒"])) ?? 10,
            startWeek: intValue(value(in: record, keys: ["startweek"])) ?? weekNumbers?.min(),
            endWeek: intValue(value(in: record, keys: ["endweek"])) ?? weekNumbers?.max(),
            activeWeeks: weekNumbers,
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
        var result = Set(mappings.compactMap { day, aliases in
            aliases.contains(where: normalized.contains) || containsNearEnglishWeekday(normalized, aliases: aliases)
                ? day
                : nil
        })
        if result.isEmpty {
            let numericDays = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
            if numericDays.range(of: #"^[1-7](?:\s*[,，、/|;；\s]\s*[1-7])*$"#, options: .regularExpression) != nil {
                for number in numericDays.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init) {
                    result.insert(Weekday.allCases[number - 1])
                }
            } else if let expression = try? NSRegularExpression(pattern: #"周\s*([1-7])(?!\s*[-–—~至到]\s*\d)"#) {
                for match in expression.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) {
                    if let range = Range(match.range(at: 1), in: normalized), let number = Int(normalized[range]) {
                        result.insert(Weekday.allCases[number - 1])
                    }
                }
            }
        }
        return result
    }

    private static func containsNearEnglishWeekday(_ text: String, aliases: [String]) -> Bool {
        let fullNames = aliases.filter { $0.count > 3 }
        guard !fullNames.isEmpty else { return false }
        let tokens = text.components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count > 3 }
        return tokens.contains { token in
            fullNames.contains { editDistance(token, $0, limit: 1) <= 1 }
        }
    }

    private static func editDistance(_ lhs: String, _ rhs: String, limit: Int) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        guard abs(left.count - right.count) <= limit else { return limit + 1 }

        var previous = Array(0...right.count)
        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = [leftIndex + 1]
            var rowMinimum = current[0]
            for (rightIndex, rightCharacter) in right.enumerated() {
                let substitution = previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                let insertion = current[rightIndex] + 1
                let deletion = previous[rightIndex + 1] + 1
                let value = min(substitution, min(insertion, deletion))
                current.append(value)
                rowMinimum = min(rowMinimum, value)
            }
            if rowMinimum > limit { return limit + 1 }
            previous = current
        }
        return previous[right.count]
    }

    static func academicWeeks(_ text: String, explicitField: Bool) -> Set<Int>? {
        let segments = text.replacingOccurrences(of: "，", with: ",").replacingOccurrences(of: "、", with: ",").split(separator: ",")
        var result = Set<Int>()
        for segment in segments {
            let value = String(segment).trimmingCharacters(in: .whitespacesAndNewlines)
            let rangePattern = explicitField ? #"(\d+)\s*[-–—~至到]\s*(\d+)(?:\s*周)?"# : #"(\d+)\s*[-–—~至到]\s*(\d+)\s*周"#
            let numbers: [Int]?
            if let range = capturedIntegers(in: value, pattern: rangePattern) { numbers = range }
            else if let single = capturedIntegers(in: value, pattern: #"(\d+)\s*周"#) { numbers = single }
            else if explicitField, let single = Int(value) { numbers = [single] }
            else { numbers = nil }
            guard let numbers, let first = numbers.first, (1...30).contains(first) else { continue }
            let last = min(30, max(first, numbers.dropFirst().first ?? first))
            for week in first...last where (!value.contains("单") || week % 2 == 1) && (!value.contains("双") || week % 2 == 0) {
                result.insert(week)
            }
        }
        return result.isEmpty ? nil : result
    }

    private static func explicitSectionRange(_ text: String) -> (Int, Int)? {
        if let range = sectionRange(text) { return range }
        if let values = capturedIntegers(in: text, pattern: #"^\s*(\d+)\s*[-–—~至到]\s*(\d+)\s*$"#), values.count == 2 {
            return (values[0], max(values[0], values[1]))
        }
        if let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) { return (value, value) }
        return nil
    }

    private static func sectionRange(_ text: String) -> (Int, Int)? {
        guard let values = capturedIntegers(in: text, pattern: #"第?\s*(\d+)\s*[-–—~至到]\s*(\d+)\s*节"#), values.count >= 2 else {
            return nil
        }
        return (values[0], max(values[0], values[1]))
    }

    private static func capturedIntegers(in text: String, pattern: String) -> [Int]? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return Int(text[range])
        }
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
        guard let line = lines.first(where: { $0.uppercased().hasPrefix(key + ":") || $0.uppercased().hasPrefix(key + ";") }) else { return nil }
        return parseICSDate(icsValue(key, in: lines), header: line)
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

private final class PDFUnicodeTextCollector {
    let fonts: CGPDFDictionaryRef?
    var unicodeFont = false
    var lines: [String] = []

    init(fonts: CGPDFDictionaryRef?) { self.fonts = fonts }

    private func decode(_ string: CGPDFStringRef) -> String? {
        guard unicodeFont, let bytes = CGPDFStringGetBytePtr(string) else { return nil }
        let length = CGPDFStringGetLength(string)
        guard length > 0, length % 2 == 0 else { return nil }
        return String(data: Data(bytes: bytes, count: length), encoding: .utf16BigEndian)
    }

    static let selectFont: CGPDFOperatorCallback = { scanner, info in
        guard let info else { return }
        let collector = Unmanaged<PDFUnicodeTextCollector>.fromOpaque(info).takeUnretainedValue()
        collector.unicodeFont = false
        var size: CGPDFReal = 0
        var fontName: UnsafePointer<CChar>?
        guard CGPDFScannerPopNumber(scanner, &size), CGPDFScannerPopName(scanner, &fontName),
              let fontName, let fonts = collector.fonts else { return }
        var font: CGPDFDictionaryRef?
        var encoding: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetDictionary(fonts, fontName, &font), let font,
              CGPDFDictionaryGetName(font, "Encoding", &encoding), let encoding else { return }
        collector.unicodeFont = ["UniGB-UCS2-H", "UniGB-UCS2-V", "UniGB-UTF16-H", "UniGB-UTF16-V"]
            .contains(String(cString: encoding))
    }

    static let showText: CGPDFOperatorCallback = { scanner, info in
        guard let info else { return }
        let collector = Unmanaged<PDFUnicodeTextCollector>.fromOpaque(info).takeUnretainedValue()
        var value: CGPDFStringRef?
        if CGPDFScannerPopString(scanner, &value), let value, let text = collector.decode(value) {
            collector.lines.append(text)
        }
    }

    static let showTextArray: CGPDFOperatorCallback = { scanner, info in
        guard let info else { return }
        let collector = Unmanaged<PDFUnicodeTextCollector>.fromOpaque(info).takeUnretainedValue()
        var array: CGPDFArrayRef?
        guard CGPDFScannerPopArray(scanner, &array), let array else { return }
        var pieces: [String] = []
        for index in 0..<CGPDFArrayGetCount(array) {
            var value: CGPDFStringRef?
            if CGPDFArrayGetString(array, index, &value), let value, let text = collector.decode(value) {
                pieces.append(text)
            }
        }
        if !pieces.isEmpty { collector.lines.append(pieces.joined()) }
    }
}
