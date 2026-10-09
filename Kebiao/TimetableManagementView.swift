import SwiftUI

struct TimetableManagementView: View {
    let store: TimetableStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var creating = false
    @State private var renaming: Timetable?
    @State private var deleting: Timetable?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.timetables) { table in
                        HStack {
                            Button {
                                if store.selectTimetable(id: table.id) { dismiss() }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(table.name).foregroundStyle(.primary)
                                        Text("\(table.courses.count) 门课程 · \(table.weekCount) 周")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if table.id == store.activeTimetableID { Image(systemName: "checkmark.circle.fill") }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("timetable-select-\(table.id)")
                            Menu {
                                Button("重命名") { name = table.name; renaming = table }
                                Button("复制课表") { store.duplicateTimetable(id: table.id) }
                                Button("删除课表", role: .destructive) { deleting = table }
                                    .disabled(store.timetables.count <= 1)
                            } label: { Image(systemName: "ellipsis.circle").padding(8) }
                        }
                        .disabled(store.isReadOnly)
                    }
                } footer: {
                    Text("每张课表独立保存课程、学期和作息。通知、小组件与实时活动跟随当前选择。")
                }
                Button { name = ""; creating = true } label: { Label("新建课表", systemImage: "plus") }
                    .disabled(store.isReadOnly).accessibilityIdentifier("timetable-create")
                if let error = store.errorMessage { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("管理课表")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
            .alert("新建课表", isPresented: $creating) {
                TextField("课表名称", text: $name)
                Button("取消", role: .cancel) { }
                Button("新建") { store.addTimetable(name: name) }
            }
            .alert("重命名课表", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("课表名称", text: $name)
                Button("取消", role: .cancel) { renaming = nil }
                Button("保存") {
                    if var table = renaming { table.name = name; store.updateTimetable(table) }
                    renaming = nil
                }
            }
            .alert("删除这张课表？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("取消", role: .cancel) { deleting = nil }
                Button("删除", role: .destructive) {
                    if let table = deleting { store.deleteTimetable(id: table.id) }
                    deleting = nil
                }
            } message: { Text("课表中的课程和调整记录会一起删除。可先导出备份。") }
        }
    }
}

struct TimetableSettingsView: View {
    let store: TimetableStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Timetable

    init(store: TimetableStore) {
        self.store = store
        _draft = State(initialValue: store.activeTimetable)
    }

    private var validationError: String? {
        do { try draft.validate(); return nil } catch { return error.localizedDescription }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("课表与学期") {
                    TextField("课表名称", text: $draft.name).accessibilityIdentifier("timetable-name")
                    DatePicker("第一周所在日期", selection: $draft.semesterStartDate, displayedComponents: .date)
                    Stepper("本学期 \(draft.weekCount) 周", value: $draft.weekCount, in: 1...30)
                    Text("第一周按周一开始计算。更改学期日期只影响这张课表。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    ForEach($draft.sectionPeriods) { $period in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("第 \(period.id) 节").font(.headline)
                            MinutePickerRow(title: "开始", minutes: $period.startMinutes, calendar: draft.calendar)
                            MinutePickerRow(title: "结束", minutes: $period.endMinutes, calendar: draft.calendar)
                        }.padding(.vertical, 4)
                    }
                } header: { Text("学校作息 · 12 节") } footer: {
                    Text("默认课程使用首节开始到末节结束的时间，包含课间和午休。显式自定义的课程时间与时长优先。")
                }
                if let error = validationError ?? store.errorMessage { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            .environment(\.timeZone, draft.calendar.timeZone)
            .navigationTitle("课表设置")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { if store.updateTimetable(draft) { dismiss() } }
                        .disabled(validationError != nil || store.isReadOnly).accessibilityIdentifier("timetable-settings-save")
                }
            }
        }
    }
}

private struct MinutePickerRow: View {
    let title: String
    @Binding var minutes: Int
    let calendar: Calendar
    var body: some View {
        DatePicker(title, selection: Binding(
            get: { calendar.date(byAdding: .minute, value: minutes, to: calendar.startOfDay(for: .now)) ?? .now },
            set: { let parts = calendar.dateComponents([.hour, .minute], from: $0); minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0) }
        ), displayedComponents: .hourAndMinute)
    }
}

struct OccurrenceAdjustmentView: View {
    let store: TimetableStore
    let occurrence: CourseOccurrence
    @Environment(\.dismiss) private var dismiss
    @State private var cancelClass = false
    @State private var start: Date
    @State private var end: Date
    @State private var location: String
    @State private var teacher: String

    init(store: TimetableStore, occurrence: CourseOccurrence) {
        self.store = store; self.occurrence = occurrence
        _start = State(initialValue: occurrence.startDate); _end = State(initialValue: occurrence.endDate)
        _location = State(initialValue: occurrence.course.location); _teacher = State(initialValue: occurrence.course.teacher)
    }
    private var existing: Bool {
        store.timetable(id: occurrence.timetableID)?.courses.first { $0.id == occurrence.course.id }?.exceptions
            .contains { $0.slotID == occurrence.slotID && $0.source == occurrence.source } ?? false
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(occurrence.course.name).font(.headline)
                    Text("仅修改这一次安排，其他周次和时段保持原有规则。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Toggle("本次停课", isOn: $cancelClass)
                }
                if !cancelClass {
                    Section("调整安排") {
                        DatePicker("开始", selection: $start)
                        DatePicker("结束", selection: $end)
                        TextField("教室", text: $location)
                        TextField("教师", text: $teacher)
                        if end <= start { Text("结束时间需要晚于开始时间。").foregroundStyle(.red) }
                    }
                }
                if existing {
                    Button("恢复本次原安排", role: .destructive) {
                        if store.restoreOccurrence(occurrence) { dismiss() }
                    }
                }
                if let error = store.errorMessage { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .environment(\.timeZone, store.timetable(id: occurrence.timetableID)?.calendar.timeZone ?? .current)
            .navigationTitle("仅调整本次")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let exception = CourseException(slotID: occurrence.slotID, source: occurrence.source,
                            action: cancelClass ? .cancelled : .replaced, startDate: cancelClass ? nil : start,
                            endDate: cancelClass ? nil : end, teacher: teacher, location: location)
                        if store.setException(exception, for: occurrence) { dismiss() }
                    }.disabled(store.isReadOnly || (!cancelClass && end <= start))
                }
            }
        }
    }
}
