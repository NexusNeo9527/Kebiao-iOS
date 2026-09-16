import SwiftUI
import UIKit

struct CoursesView: View {
    let store: TimetableStore
    @State private var presentedSheet: CourseSheet?

    var body: some View {
        ZStack {
            KebiaoTheme.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 12) {
                    if store.courses.isEmpty {
                        ContentUnavailableView(
                            "还没有课程",
                            systemImage: "books.vertical",
                            description: Text("添加一门课程，或从学校教务系统导入课表。")
                        )
                        .padding(.top, 90)
                    } else {
                        ForEach(store.courses.sorted { $0.name < $1.name }) { course in
                            Button { presentedSheet = .edit(course) } label: {
                                courseRow(course)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(18)
                .padding(.bottom, 30)
            }
        }
        .navigationTitle("课程")
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("--ui-test-import"), presentedSheet == nil {
                presentedSheet = .importSchedule
            } else if ProcessInfo.processInfo.arguments.contains("--ui-test-add-course"), presentedSheet == nil {
                presentedSheet = .create
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { presentedSheet = .importSchedule } label: {
                    Image(systemName: "tray.and.arrow.down")
                }
                .accessibilityLabel("导入学校课表")
                Button { presentedSheet = .create } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加课程")
            }
        }
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case .create:
                CourseEditorView(course: nil, store: store)
            case .edit(let course):
                CourseEditorView(course: course, store: store)
            case .importSchedule:
                ImportScheduleView(store: store)
            }
        }
    }

    private func courseRow(_ course: Course) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 3)
                .fill(course.color)
                .frame(width: 6, height: 56)
            VStack(alignment: .leading, spacing: 7) {
                Text(course.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    Label(course.weekdays.sorted { $0.weekIndex < $1.weekIndex }.map(\.shortName).joined(separator: "、"), systemImage: "calendar")
                    Label("第\(course.startSection)–\(course.endSection)节", systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: KebiaoTheme.cardRadius, style: .continuous))
    }
}

struct CourseEditorView: View {
    let course: Course?
    let store: TimetableStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Course
    @State private var showingDeleteConfirmation = false

    init(course: Course?, store: TimetableStore) {
        self.course = course
        self.store = store
        _draft = State(initialValue: course ?? Course(
            name: "",
            teacher: "",
            location: "",
            startSection: 1,
            sectionCount: 2,
            weekdays: [.monday],
            colorValue: 0xFF4B68,
            startTimeMinutes: nil,
            reminderMinutesBefore: 10,
            startWeek: 1,
            endWeek: 20
        ))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                KebiaoTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        identityCard
                        periodCard
                        reminderCard
                        if course != nil { managementButtons }
                    }
                    .padding(18)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle(course == nil ? "添加课程" : "编辑课程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("关闭")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { store.save(draft); dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(KebiaoTheme.accent)
                        .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog("删除这门课程？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("删除课程", role: .destructive) {
                    if let course { store.delete(course) }
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("此操作会同时更新提醒和灵动岛中的下一节课。")
            }
        }
    }

    private var identityCard: some View {
        VStack(spacing: 0) {
            TextField("输入课程名称", text: $draft.name)
                .font(.title2.weight(.semibold))
                .padding(.vertical, 22)

            Divider()
            editorRow(icon: "paintpalette", title: "颜色") {
                ColorPicker("颜色", selection: colorBinding, supportsOpacity: false)
                    .labelsHidden()
            }
            Divider()
            editorRow(icon: "star.circle", title: "学分") {
                TextField("选填", text: creditsBinding)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .foregroundStyle(.secondary)
                    .frame(width: 90)
            }
        }
        .padding(.horizontal, 18)
        .background(.white, in: RoundedRectangle(cornerRadius: KebiaoTheme.cardRadius, style: .continuous))
    }

    private var periodCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("时段 1")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)

            VStack(spacing: 0) {
                editorRow(icon: "calendar", title: "周数") {
                    HStack(spacing: 4) {
                        counterControl(value: startWeekBinding, range: 1...30, label: "开始周")
                        Text("–")
                        counterControl(value: endWeekBinding, range: draft.resolvedStartWeek...30, label: "结束周")
                        Text("周")
                    }
                    .font(.subheadline)
                }
                Divider()

                VStack(alignment: .leading, spacing: 13) {
                    Label("上课日", systemImage: "calendar.day.timeline.left")
                        .font(.body)
                    HStack(spacing: 6) {
                        ForEach(Weekday.allCases) { day in
                            Button {
                                if draft.weekdays.contains(day), draft.weekdays.count > 1 {
                                    draft.weekdays.remove(day)
                                } else {
                                    draft.weekdays.insert(day)
                                }
                            } label: {
                                Text(day.shortName.replacingOccurrences(of: "周", with: ""))
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 34)
                                    .foregroundStyle(draft.weekdays.contains(day) ? .white : .secondary)
                                    .background(draft.weekdays.contains(day) ? KebiaoTheme.accent : KebiaoTheme.background, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(day.fullName)
                            .accessibilityAddTraits(draft.weekdays.contains(day) ? .isSelected : [])
                        }
                    }
                }
                .padding(.vertical, 16)
                Divider()

                editorRow(icon: "clock", title: "节数") {
                    HStack(spacing: 5) {
                        Text("从")
                        counterControl(value: $draft.startSection, range: 1...12, label: "开始节次")
                        Text("起")
                        counterControl(value: $draft.sectionCount, range: 1...min(4, 13 - draft.startSection), label: "连续节数")
                        Text("节")
                    }
                    .font(.subheadline)
                }
                .onChange(of: draft.startSection) { _, _ in
                    draft.sectionCount = min(draft.sectionCount, 13 - draft.startSection)
                }
                Divider()

                editorRow(icon: "pencil.and.outline", title: "自定义时间") {
                    Toggle("自定义时间", isOn: customTimeEnabled).labelsHidden()
                }
                if draft.startTimeMinutes != nil {
                    DatePicker("开始时间", selection: startTime, displayedComponents: .hourAndMinute)
                        .padding(.bottom, 14)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                Divider()

                fieldRow(icon: "mappin.and.ellipse", title: "教室", text: $draft.location)
                Divider()
                fieldRow(icon: "person", title: "老师", text: $draft.teacher)
                Divider()
                fieldRow(icon: "note.text", title: "备注", text: notesBinding)
            }
            .padding(.horizontal, 18)
            .background(.white, in: RoundedRectangle(cornerRadius: KebiaoTheme.cardRadius, style: .continuous))
        }
    }

    private var reminderCard: some View {
        VStack(spacing: 0) {
            editorRow(icon: "bell", title: "上课前提醒") {
                Toggle("提醒", isOn: reminderEnabled).labelsHidden()
            }
            if draft.reminderMinutesBefore != nil {
                Divider()
                editorRow(icon: "timer", title: "提前时间") {
                    Stepper("\(draft.reminderMinutesBefore ?? 10) 分钟", value: reminderLeadTime, in: 1...120)
                        .font(.subheadline)
                }
            }
        }
        .padding(.horizontal, 18)
        .background(.white, in: RoundedRectangle(cornerRadius: KebiaoTheme.cardRadius, style: .continuous))
    }

    private var managementButtons: some View {
        HStack(spacing: 12) {
            Button {
                store.duplicate(draft)
                dismiss()
            } label: {
                Label("复制课程", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("删除", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .buttonBorderShape(.roundedRectangle(radius: 14))
    }

    private func editorRow<Accessory: View>(icon: String, title: String, @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon).frame(width: 23).foregroundStyle(.primary)
            Text(title).fixedSize(horizontal: true, vertical: false)
            Spacer()
            accessory()
        }
        .frame(minHeight: 56)
    }

    private func fieldRow(icon: String, title: String, text: Binding<String>) -> some View {
        editorRow(icon: icon, title: title) {
            TextField("选填", text: text)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
        }
    }

    private func counterControl(value: Binding<Int>, range: ClosedRange<Int>, label: String) -> some View {
        HStack(spacing: 0) {
            Button {
                value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1)
            } label: {
                Image(systemName: "minus").frame(width: 28, height: 32)
            }
            .disabled(value.wrappedValue <= range.lowerBound)
            Text("\(value.wrappedValue)")
                .monospacedDigit()
                .frame(minWidth: 22)
            Button {
                value.wrappedValue = min(range.upperBound, value.wrappedValue + 1)
            } label: {
                Image(systemName: "plus").frame(width: 28, height: 32)
            }
            .disabled(value.wrappedValue >= range.upperBound)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.primary)
        .background(KebiaoTheme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label)，\(value.wrappedValue)")
    }

    private var startWeekBinding: Binding<Int> {
        Binding(
            get: { draft.resolvedStartWeek },
            set: { draft.startWeek = $0; draft.endWeek = max($0, draft.resolvedEndWeek) }
        )
    }

    private var endWeekBinding: Binding<Int> {
        Binding(get: { draft.resolvedEndWeek }, set: { draft.endWeek = $0 })
    }

    private var creditsBinding: Binding<String> {
        Binding(
            get: { draft.credits.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? "" },
            set: { draft.credits = Double($0.replacingOccurrences(of: ",", with: ".")) }
        )
    }

    private var notesBinding: Binding<String> {
        Binding(get: { draft.notes ?? "" }, set: { draft.notes = $0.isEmpty ? nil : $0 })
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { draft.color },
            set: { draft.colorValue = $0.hexValue ?? draft.colorValue }
        )
    }

    private var customTimeEnabled: Binding<Bool> {
        Binding(
            get: { draft.startTimeMinutes != nil },
            set: { enabled in
                withAnimation(.snappy) {
                    draft.startTimeMinutes = enabled ? draft.resolvedStartTimeMinutes : nil
                }
            }
        )
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
        Binding(
            get: { draft.reminderMinutesBefore != nil },
            set: { draft.reminderMinutesBefore = $0 ? (draft.reminderMinutesBefore ?? 10) : nil }
        )
    }

    private var reminderLeadTime: Binding<Int> {
        Binding(get: { draft.reminderMinutesBefore ?? 10 }, set: { draft.reminderMinutesBefore = $0 })
    }
}

private enum CourseSheet: Identifiable {
    case create
    case edit(Course)
    case importSchedule

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let course): course.id.uuidString
        case .importSchedule: "import"
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
