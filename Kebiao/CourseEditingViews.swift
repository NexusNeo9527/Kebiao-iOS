import SwiftUI

enum CourseScheduleText {
    static func weeks(for slot: CourseTimeSlot) -> String {
        guard slot.datedEvents == nil else { return "具体日期安排" }
        let values = (slot.activeWeeks ?? Set(slot.resolvedStartWeek...slot.resolvedEndWeek)).sorted()
        guard let first = values.first else { return "未选择周次" }
        var ranges: [String] = []
        var start = first
        var end = first
        for value in values.dropFirst() {
            if value == end + 1 { end = value }
            else { ranges.append(start == end ? "\(start)" : "\(start)–\(end)"); start = value; end = value }
        }
        ranges.append(start == end ? "\(start)" : "\(start)–\(end)")
        return "第 " + ranges.joined(separator: "、") + " 周"
    }

    static func summary(for course: Course) -> String {
        course.timeSlots.enumerated().map { index, slot in
            let prefix = course.timeSlots.count > 1 ? "时段\(index + 1)：" : ""
            if let dates = slot.datedEvents { return prefix + "\(dates.count)次具体日期" }
            let days = slot.weekdays.sorted { $0.weekIndex < $1.weekIndex }.map(\.shortName).joined(separator: "、")
            return prefix + "\(days) · \(slot.startSection)–\(slot.endSection)节"
        }.joined(separator: "；")
    }

    static func isValid(_ course: Course) -> Bool {
        !course.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !course.timeSlots.isEmpty &&
            course.timeSlots.allSatisfy { slot in
                if let dates = slot.datedEvents {
                    return !dates.isEmpty && dates.allSatisfy { $0.endDate > $0.startDate }
                }
                return !slot.weekdays.isEmpty && (slot.activeWeeks?.isEmpty != true)
            }
    }
}

private enum WeekSelectionMode: String, CaseIterable, Identifiable {
    case every = "每周", odd = "单周", even = "双周", custom = "自选周"
    var id: String { rawValue }
}

struct WeekSelectionView: View {
    @Binding var slot: CourseTimeSlot
    let maximumWeek: Int
    @State private var mode: WeekSelectionMode

    init(slot: Binding<CourseTimeSlot>, maximumWeek: Int = 30) {
        _slot = slot
        self.maximumWeek = min(30, max(1, maximumWeek))
        let value = slot.wrappedValue
        let range = Set(value.resolvedStartWeek...value.resolvedEndWeek)
        let current = value.activeWeeks ?? range
        let initial: WeekSelectionMode = current == range ? .every :
            (current == Set(range.filter { $0 % 2 == 1 }) ? .odd :
                (current == Set(range.filter { $0 % 2 == 0 }) ? .even : .custom))
        _mode = State(initialValue: initial)
    }

    private var upperLimit: Int { min(30, max(maximumWeek, max(slot.resolvedEndWeek, slot.activeWeeks?.max() ?? 1))) }
    private var selectedWeeks: Set<Int> { slot.activeWeeks ?? Set(slot.resolvedStartWeek...slot.resolvedEndWeek) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("周次模式", selection: $mode) {
                ForEach(WeekSelectionMode.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
                .onChange(of: mode) { _, _ in applyMode() }
            Stepper("开始：第 \(slot.resolvedStartWeek) 周", value: startBinding, in: 1...upperLimit)
            Stepper("结束：第 \(slot.resolvedEndWeek) 周", value: endBinding,
                in: slot.resolvedStartWeek...upperLimit)
            if mode == .custom {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 40))], spacing: 8) {
                    ForEach(1...upperLimit, id: \.self) { week in
                        Button {
                            var weeks = selectedWeeks
                            if weeks.contains(week) { weeks.remove(week) } else { weeks.insert(week) }
                            slot.activeWeeks = weeks
                            if !weeks.isEmpty { slot.startWeek = weeks.min(); slot.endWeek = weeks.max() }
                        } label: {
                            Text("\(week)").font(.subheadline.monospacedDigit().weight(.medium))
                                .frame(maxWidth: .infinity).frame(height: 36)
                                .foregroundStyle(selectedWeeks.contains(week) ? Color.white : Color.secondary)
                                .background(selectedWeeks.contains(week) ? KebiaoTheme.accent : KebiaoTheme.background,
                                    in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain).accessibilityLabel("第\(week)周")
                            .accessibilityAddTraits(selectedWeeks.contains(week) ? .isSelected : [])
                    }
                }
            }
            Text(CourseScheduleText.weeks(for: slot)).font(.caption)
                .foregroundStyle(selectedWeeks.isEmpty ? Color.red : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var startBinding: Binding<Int> {
        Binding(get: { slot.resolvedStartWeek }, set: { value in
            slot.startWeek = value
            slot.endWeek = max(value, slot.resolvedEndWeek)
            applyMode()
        })
    }
    private var endBinding: Binding<Int> {
        Binding(get: { slot.resolvedEndWeek }, set: { slot.endWeek = $0; applyMode() })
    }
    private func applyMode() {
        let range = Set(slot.resolvedStartWeek...slot.resolvedEndWeek)
        switch mode {
        case .every: slot.activeWeeks = nil
        case .odd: slot.activeWeeks = Set(range.filter { $0 % 2 == 1 })
        case .even: slot.activeWeeks = Set(range.filter { $0 % 2 == 0 })
        case .custom: slot.activeWeeks = selectedWeeks.intersection(range)
        }
    }
}

struct CourseTimeSlotEditor: View {
    @Binding var slot: CourseTimeSlot
    let number: Int
    let timetable: Timetable
    var canDelete = false
    var onDuplicate: (() -> Void)?
    var onDelete: (() -> Void)?
    private var calendar: Calendar { timetable.calendar }

    var body: some View {
        KebiaoCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("时段 \(number)").font(.headline)
                    Spacer()
                    if let onDuplicate { Button(action: onDuplicate) { Image(systemName: "doc.on.doc") }.accessibilityLabel("复制时段\(number)") }
                    if canDelete, let onDelete {
                        Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.accessibilityLabel("删除时段\(number)")
                    }
                }
                Picker("安排方式", selection: datedBinding) {
                    Text("按周重复").tag(false)
                    Text("具体日期 / 补课").tag(true)
                }.pickerStyle(.segmented)
                if slot.datedEvents == nil {
                    WeekSelectionView(slot: $slot, maximumWeek: timetable.weekCount)
                    Divider()
                    weekdaySelector
                } else {
                    datedEventEditor
                }
                Divider()
                Stepper("开始：第 \(slot.startSection) 节", value: $slot.startSection, in: 1...12)
                    .onChange(of: slot.startSection) { _, value in slot.sectionCount = min(slot.sectionCount, 13 - value) }
                Stepper("连续 \(slot.sectionCount) 节", value: $slot.sectionCount, in: 1...(13 - slot.startSection))
                if slot.endSection > timetable.sectionPeriods.count {
                    Text("本课表作息仅有 \(timetable.sectionPeriods.count) 节，请校正节次或先完善作息。").font(.caption).foregroundStyle(.orange)
                }
                if slot.datedEvents == nil {
                    Toggle("自定义开始时间", isOn: customTimeEnabled)
                    if slot.startTimeMinutes != nil { DatePicker("开始时间", selection: customStartTime, displayedComponents: .hourAndMinute) }
                    Toggle("自定义时长", isOn: customDurationEnabled)
                    if slot.durationMinutes != nil {
                        Stepper("时长 \(slot.durationMinutes ?? 90) 分钟", value: durationBinding, in: 1...1440, step: 5)
                    } else {
                        Text("按学校作息使用首节开始至末节结束的实际时间。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
                TextField("教室（选填）", text: $slot.location)
                TextField("教师（选填）", text: $slot.teacher)
                Divider()
                Toggle("上课前提醒", isOn: reminderEnabled)
                if slot.reminderMinutesBefore != nil {
                    Stepper("提前 \(slot.reminderMinutesBefore ?? 10) 分钟", value: reminderBinding, in: 1...120)
                }
            }.environment(\.calendar, calendar).environment(\.timeZone, calendar.timeZone)
        }
    }

    private var weekdaySelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("上课日", systemImage: "calendar.day.timeline.left")
            HStack(spacing: 6) {
                ForEach(Weekday.allCases) { day in
                    Button {
                        if slot.weekdays.contains(day), slot.weekdays.count > 1 { slot.weekdays.remove(day) }
                        else { slot.weekdays.insert(day) }
                    } label: {
                        Text(day.shortName.replacingOccurrences(of: "周", with: ""))
                            .font(.caption.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 34)
                            .foregroundStyle(slot.weekdays.contains(day) ? Color.white : Color.secondary)
                            .background(slot.weekdays.contains(day) ? KebiaoTheme.accent : KebiaoTheme.background, in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel(day.fullName)
                        .accessibilityAddTraits(slot.weekdays.contains(day) ? .isSelected : [])
                }
            }
        }
    }

    private var datedEventEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(slot.datedEvents ?? []) { event in
                VStack(alignment: .leading, spacing: 8) {
                    DatePicker("开始", selection: eventDateBinding(event.id, isEnd: false), displayedComponents: [.date, .hourAndMinute])
                    DatePicker("结束", selection: eventDateBinding(event.id, isEnd: true), displayedComponents: [.date, .hourAndMinute])
                    if event.endDate <= event.startDate { Text("结束时间须晚于开始时间").font(.caption).foregroundStyle(.red) }
                    HStack {
                        Button("复制日期") {
                            var copy = event
                            copy.id = UUID()
                            slot.datedEvents?.append(copy)
                        }.font(.caption)
                        Spacer()
                        Button("删除日期", role: .destructive) { slot.datedEvents?.removeAll { $0.id == event.id } }
                            .font(.caption).disabled((slot.datedEvents?.count ?? 0) <= 1)
                    }
                }
                Divider()
            }
            Button { slot.datedEvents?.append(newDatedEvent()) } label: { Label("添加具体日期", systemImage: "calendar.badge.plus") }
        }
    }

    private func newDatedEvent() -> DatedCourseEvent {
        let start = calendar.date(byAdding: .minute, value: defaultStartMinutes,
            to: calendar.startOfDay(for: .now)) ?? .now
        return DatedCourseEvent(startDate: start, endDate: start.addingTimeInterval(Double(defaultDurationMinutes) * 60))
    }
    private func eventDateBinding(_ id: UUID, isEnd: Bool) -> Binding<Date> {
        Binding(get: {
            guard let value = slot.datedEvents?.first(where: { $0.id == id }) else { return .now }
            return isEnd ? value.endDate : value.startDate
        }, set: { value in
            guard let index = slot.datedEvents?.firstIndex(where: { $0.id == id }) else { return }
            if isEnd { slot.datedEvents?[index].endDate = value } else { slot.datedEvents?[index].startDate = value }
        })
    }
    private var defaultStartMinutes: Int {
        slot.startTimeMinutes ?? timetable.sectionPeriods.first(where: { $0.id == slot.startSection })?.startMinutes
            ?? SectionSchedule.startMinutes(for: slot.startSection)
    }
    private var defaultDurationMinutes: Int {
        if let duration = slot.durationMinutes { return duration }
        let end = timetable.sectionPeriods.first(where: { $0.id == slot.endSection })?.endMinutes
            ?? (SectionSchedule.startMinutes(for: slot.endSection) + 45)
        let start = timetable.sectionPeriods.first(where: { $0.id == slot.startSection })?.startMinutes
            ?? SectionSchedule.startMinutes(for: slot.startSection)
        return max(1, end - start)
    }
    private var datedBinding: Binding<Bool> {
        Binding(get: { slot.datedEvents != nil }, set: { value in slot.datedEvents = value ? [newDatedEvent()] : nil })
    }
    private var customTimeEnabled: Binding<Bool> {
        Binding(get: { slot.startTimeMinutes != nil }, set: { slot.startTimeMinutes = $0 ? defaultStartMinutes : nil })
    }
    private var customDurationEnabled: Binding<Bool> {
        Binding(get: { slot.durationMinutes != nil }, set: { slot.durationMinutes = $0 ? defaultDurationMinutes : nil })
    }
    private var customStartTime: Binding<Date> {
        Binding(get: { calendar.date(byAdding: .minute, value: defaultStartMinutes, to: calendar.startOfDay(for: .now)) ?? .now },
            set: { value in
                let parts = calendar.dateComponents([.hour, .minute], from: value)
                slot.startTimeMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            })
    }
    private var durationBinding: Binding<Int> {
        Binding(get: { slot.durationMinutes ?? defaultDurationMinutes }, set: { slot.durationMinutes = $0 })
    }
    private var reminderEnabled: Binding<Bool> {
        Binding(get: { slot.reminderMinutesBefore != nil }, set: { slot.reminderMinutesBefore = $0 ? 10 : nil })
    }
    private var reminderBinding: Binding<Int> {
        Binding(get: { slot.reminderMinutesBefore ?? 10 }, set: { slot.reminderMinutesBefore = $0 })
    }
}
