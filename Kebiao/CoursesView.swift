import SwiftUI
import UIKit

struct CoursesView: View {
    let store: TimetableStore
    @State private var presentedSheet: CourseSheet?

    var body: some View {
        List {
            if store.courses.isEmpty {
                ContentUnavailableView("还没有课程", systemImage: "books.vertical", description: Text("点右上角添加第一门课程。"))
            } else {
                ForEach(store.courses.sorted { $0.name < $1.name }) { course in
                    Button { presentedSheet = .edit(course) } label: {
                        HStack(spacing: 12) {
                            Circle().fill(course.color).frame(width: 12, height: 12)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(course.name).foregroundStyle(.primary)
                                Text("\(course.weekdays.sorted { $0.weekIndex < $1.weekIndex }.map(\.shortName).joined(separator: "、")) · 第\(course.startSection)节")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
                .onDelete { offsets in
                    let ordered = store.courses.sorted { $0.name < $1.name }
                    for offset in offsets { store.delete(ordered[offset]) }
                }
            }
        }
        .navigationTitle("课程")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { presentedSheet = .create } label: { Image(systemName: "plus") }
                    .accessibilityLabel("添加课程")
            }
        }
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case .create:
                CourseEditorView(course: nil, store: store)
            case .edit(let course):
                CourseEditorView(course: course, store: store)
            }
        }
    }
}

struct CourseEditorView: View {
    let course: Course?
    let store: TimetableStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Course

    init(course: Course?, store: TimetableStore) {
        self.course = course
        self.store = store
        _draft = State(initialValue: course ?? Course(name: "", teacher: "", location: "", startSection: 1, sectionCount: 2, weekdays: [.monday], colorValue: 0x5477D9, startTimeMinutes: nil, reminderMinutesBefore: 10))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("课程信息") {
                    TextField("课程名称", text: $draft.name)
                    TextField("授课教师", text: $draft.teacher)
                    TextField("上课地点", text: $draft.location)
                }
                Section("时间") {
                    Stepper("第 \(draft.startSection) 节开始", value: $draft.startSection, in: 1...12)
                        .onChange(of: draft.startSection) { _, _ in
                            draft.sectionCount = min(draft.sectionCount, 13 - draft.startSection)
                        }
                    Stepper("连续 \(draft.sectionCount) 节", value: $draft.sectionCount, in: 1...min(4, 13 - draft.startSection))
                    DatePicker("开始时间", selection: startTime, displayedComponents: .hourAndMinute)
                    Toggle("上课前提醒", isOn: reminderEnabled)
                    if draft.reminderMinutesBefore != nil {
                        Stepper("提前 \(draft.reminderMinutesBefore ?? 10) 分钟", value: reminderLeadTime, in: 1...120)
                    }
                    ForEach(Weekday.allCases) { day in
                        Toggle(day.fullName, isOn: Binding(
                            get: { draft.weekdays.contains(day) },
                            set: { enabled in
                                if enabled { draft.weekdays.insert(day) }
                                else if draft.weekdays.count > 1 { draft.weekdays.remove(day) }
                            }
                        ))
                    }
                }
                Section("颜色") {
                    ColorPicker("课程颜色", selection: Binding(
                        get: { draft.color },
                        set: { draft.colorValue = $0.hexValue ?? draft.colorValue }
                    ))
                }
            }
            .navigationTitle(course == nil ? "添加课程" : "编辑课程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { store.save(draft); dismiss() }
                        .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var startTime: Binding<Date> {
        Binding {
            Calendar.current.date(byAdding: .minute, value: draft.resolvedStartTimeMinutes, to: Calendar.current.startOfDay(for: .now)) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            draft.startTimeMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }

    private var reminderEnabled: Binding<Bool> {
        Binding {
            draft.reminderMinutesBefore != nil
        } set: { enabled in
            draft.reminderMinutesBefore = enabled ? (draft.reminderMinutesBefore ?? 10) : nil
        }
    }

    private var reminderLeadTime: Binding<Int> {
        Binding(
            get: { draft.reminderMinutesBefore ?? 10 },
            set: { draft.reminderMinutesBefore = $0 }
        )
    }
}

private enum CourseSheet: Identifiable {
    case create
    case edit(Course)

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let course): course.id.uuidString
        }
    }
}

private extension Color {
    var hexValue: Int? {
        guard let components = UIColor(self).cgColor.components else { return nil }
        let values = components.count == 2 ? [components[0], components[0], components[0]] : components
        guard values.count >= 3 else { return nil }
        return (Int(values[0] * 255) << 16) | (Int(values[1] * 255) << 8) | Int(values[2] * 255)
    }
}
