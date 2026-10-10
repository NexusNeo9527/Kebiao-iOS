import SwiftUI

struct ImportSlotPreview {
    let slot: CourseTimeSlot
    let timetable: Timetable

    var weekdaysText: String {
        let days = slot.weekdays.sorted { $0.weekIndex < $1.weekIndex }.map(\.shortName)
        return days.isEmpty ? "未选择星期" : days.joined(separator: "、")
    }
    var weeksText: String { CourseScheduleText.weeks(for: slot) }
    var sectionsText: String { "第 \(slot.startSection)–\(slot.endSection) 节" }
    var hasMatchingPeriods: Bool {
        timetable.sectionPeriods.contains { $0.id == slot.startSection } &&
            timetable.sectionPeriods.contains { $0.id == slot.endSection }
    }
    var weeklyInterval: DateInterval? {
        guard slot.datedEvents == nil, let weekday = slot.weekdays.min(by: { $0.weekIndex < $1.weekIndex }) else { return nil }
        let week = slot.activeWeeks?.min() ?? slot.resolvedStartWeek
        let calendar = timetable.calendar
        let firstMonday = Weekday.monday.date(inWeekContaining: timetable.semesterStartDate, calendar: calendar)
        guard let day = calendar.date(byAdding: .day, value: (week - 1) * 7 + weekday.weekIndex, to: firstMonday) else { return nil }
        return ScheduleEngine.timeInterval(for: slot, on: day, in: timetable)
    }
    var weeklyTimeText: String {
        guard let interval = weeklyInterval else { return "实际时间待校正" }
        let clockFormatter = formatter("HH:mm")
        let endDay = timetable.calendar.isDate(interval.start, inSameDayAs: interval.end) ? "" : "次日 "
        return "\(clockFormatter.string(from: interval.start))–\(endDay)\(clockFormatter.string(from: interval.end))"
    }
    var sortedEvents: [DatedCourseEvent] {
        (slot.datedEvents ?? []).sorted {
            $0.startDate == $1.startDate ? $0.id.uuidString < $1.id.uuidString : $0.startDate < $1.startDate
        }
    }
    func datedTimeText(for event: DatedCourseEvent) -> String {
        let full = formatter("yyyy/MM/dd HH:mm")
        let end = timetable.calendar.isDate(event.startDate, inSameDayAs: event.endDate)
            ? formatter("HH:mm").string(from: event.endDate) : full.string(from: event.endDate)
        return "\(full.string(from: event.startDate))–\(end)"
    }
    static func originalPDFWeekHint(for course: Course) -> String? {
        let lines = course.notes?.components(separatedBy: .newlines)
            .filter { $0.contains("原始周次：") } ?? []
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
    private func formatter(_ format: String) -> DateFormatter {
        let value = DateFormatter()
        value.locale = Locale(identifier: "en_US_POSIX")
        value.calendar = timetable.calendar
        value.timeZone = timetable.calendar.timeZone
        value.dateFormat = format
        return value
    }
}

struct ImportPreviewCourseCard: View {
    let course: Course
    let timetable: Timetable
    let isPDF: Bool
    let onCorrect: () -> Void
    @State private var expandedSlotIDs: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Circle().fill(course.color).frame(width: 10, height: 10).padding(.top, 5)
                Text(course.name).font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("import-course-name-\(course.id.uuidString)")
                Button("校正", action: onCorrect).font(.caption).buttonStyle(.bordered)
                    .accessibilityLabel("校正\(course.name)的星期、节次和周次")
                    .accessibilityIdentifier("import-correct-\(course.id.uuidString)")
            }
            ForEach(Array(course.timeSlots.enumerated()), id: \.element.id) { index, slot in
                ImportPreviewSlotDetails(slot: slot, timetable: timetable, number: index + 1,
                    isExpanded: expandedSlotIDs.contains(slot.id)) {
                    if expandedSlotIDs.contains(slot.id) { expandedSlotIDs.remove(slot.id) }
                    else { expandedSlotIDs.insert(slot.id) }
                }
            }
            if isPDF, let hint = ImportSlotPreview.originalPDFWeekHint(for: course) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("PDF 来源提示（只读）").font(.caption.weight(.medium))
                    Text(hint).font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("import-pdf-source-\(course.id.uuidString)")
                }.foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KebiaoTheme.background, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ImportPreviewSlotDetails: View {
    let slot: CourseTimeSlot
    let timetable: Timetable
    let number: Int
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    private var details: ImportSlotPreview { ImportSlotPreview(slot: slot, timetable: timetable) }
    private var visibleEvents: [DatedCourseEvent] {
        isExpanded ? details.sortedEvents : Array(details.sortedEvents.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("时段 \(number) · \(details.sectionsText)").font(.caption.weight(.semibold))
            if slot.datedEvents == nil {
                Text(details.weekdaysText).font(.caption)
                    .accessibilityIdentifier("import-slot-days-\(slot.id.uuidString)")
                Text(details.weeksText).font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("import-slot-weeks-\(slot.id.uuidString)")
                Text(details.weeklyTimeText).font(.caption.monospacedDigit())
                    .accessibilityIdentifier("import-slot-time-\(slot.id.uuidString)")
                if slot.startTimeMinutes != nil || slot.durationMinutes != nil {
                    Text("使用自定义时间或时长").font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text("\(details.sortedEvents.count) 次日期安排 · \(timetable.timeZoneIdentifier)")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(visibleEvents) { event in
                    Text(details.datedTimeText(for: event)).font(.caption.monospacedDigit())
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("import-event-\(event.id.uuidString)")
                }
                if details.sortedEvents.count > 3 {
                    Button(isExpanded ? "收起日期安排" : "展开全部 \(details.sortedEvents.count) 次", action: onToggleExpanded)
                        .font(.caption).buttonStyle(.borderless)
                        .accessibilityIdentifier("import-expand-\(slot.id.uuidString)")
                }
            }
            if !details.hasMatchingPeriods {
                Label("节次与目标课表作息不匹配，请校正节次或完善作息。", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("教师：\(slot.teacher.isEmpty ? "未填写" : slot.teacher)").font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("教室：\(slot.location.isEmpty ? "未填写" : slot.location)").font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
