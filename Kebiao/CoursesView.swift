import SwiftUI
import UIKit

struct CoursesView: View {
    let store: TimetableStore
    var onShowSchedule: (Date) -> Void = { _ in }
    @State private var presentedSheet: CourseSheet?

    var body: some View {
        ZStack {
            KebiaoTheme.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 12) {
                    Text(store.activeTimetable.name).font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if store.courses.isEmpty {
                        ContentUnavailableView("还没有课程", systemImage: "books.vertical",
                            description: Text("添加一门课程，或从学校教务系统导入课表。")).padding(.top, 70)
                    } else {
                        ForEach(store.courses.sorted { $0.name < $1.name }) { course in
                            Button { presentedSheet = .edit(course) } label: { courseRow(course) }.buttonStyle(.plain)
                        }
                    }
                }.padding(18).padding(.bottom, 30)
            }
        }
        .navigationTitle("课程")
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-test-import") }), presentedSheet == nil {
                presentedSheet = .importSchedule
            } else if ProcessInfo.processInfo.arguments.contains("--ui-test-add-course"), presentedSheet == nil {
                presentedSheet = .create
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { presentedSheet = .importSchedule } label: { Image(systemName: "tray.and.arrow.down") }
                    .accessibilityLabel("导入学校课表").disabled(store.isReadOnly)
                Button { presentedSheet = .create } label: { Image(systemName: "plus") }
                    .accessibilityLabel("添加课程").disabled(store.isReadOnly)
            }
        }
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case .create: CourseEditorView(course: nil, store: store)
            case .edit(let course): CourseEditorView(course: course, store: store)
            case .importSchedule:
                ImportScheduleView(store: store) { date in presentedSheet = nil; onShowSchedule(date) }
            }
        }
    }

    private func courseRow(_ course: Course) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 3).fill(course.color).frame(width: 6, height: 56)
            VStack(alignment: .leading, spacing: 7) {
                Text(course.name).font(.headline).foregroundStyle(.primary).lineLimit(2)
                Text(CourseScheduleText.summary(for: course)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }.padding(18)
            .background(.white, in: RoundedRectangle(cornerRadius: KebiaoTheme.cardRadius, style: .continuous))
    }
}

struct CourseEditorView: View {
    let course: Course?
    let store: TimetableStore
    private let timetable: Timetable
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Course
    @State private var showingDeleteConfirmation = false
    @State private var saveError: String?

    init(course: Course?, store: TimetableStore, timetable: Timetable? = nil) {
        self.course = course
        self.store = store
        let target = timetable ?? store.activeTimetable
        self.timetable = target
        _draft = State(initialValue: course ?? Course(name: "", colorValue: 0xFF4B68,
            timeSlots: [CourseTimeSlot(sectionCount: min(2, target.sectionPeriods.count),
                startWeek: 1, endWeek: target.weekCount)]))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                KebiaoTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        identityCard
                        ForEach(Array(draft.timeSlots.enumerated()), id: \.element.id) { index, slot in
                            CourseTimeSlotEditor(slot: slotBinding(id: slot.id), number: index + 1, timetable: timetable,
                                canDelete: draft.timeSlots.count > 1, onDuplicate: { duplicateSlot(slot) },
                                onDelete: { draft.timeSlots.removeAll { $0.id == slot.id }; draft.exceptions.removeAll { $0.slotID == slot.id } })
                        }
                        Button {
                            let slot = CourseTimeSlot(sectionCount: min(2, timetable.sectionPeriods.count),
                                startWeek: 1, endWeek: timetable.weekCount)
                            draft.timeSlots.append(slot)
                        } label: {
                            Label("添加上课时段", systemImage: "plus.circle").frame(maxWidth: .infinity).padding(.vertical, 8)
                        }.buttonStyle(.bordered).tint(KebiaoTheme.accent)
                        if !draft.exceptions.isEmpty { adjustmentHistory }
                        if course != nil { managementButtons }
                    }.padding(18).padding(.bottom, 30).disabled(store.isReadOnly)
                }
                .accessibilityIdentifier("course-editor-scroll")
            }
            .navigationTitle(course == nil ? "添加课程" : "编辑整门课").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if store.save(draft, into: timetable.id) { dismiss() }
                        else { saveError = store.errorMessage ?? "课程未能保存，请重试。" }
                    }.fontWeight(.semibold).foregroundStyle(KebiaoTheme.accent)
                        .disabled(!CourseScheduleText.isValid(draft) || store.isReadOnly)
                }
            }
            .confirmationDialog("删除这门课程？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("删除课程", role: .destructive) {
                    if let course, !store.delete(course, from: timetable.id) { saveError = store.errorMessage; return }
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: { Text("这门课程的全部时段和临时调整也会删除。") }
            .alert("无法保存", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("知道了", role: .cancel) { saveError = nil }
            } message: { Text(saveError ?? "") }
        }
    }

    private var identityCard: some View {
        KebiaoCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(timetable.name).font(.caption).foregroundStyle(.secondary)
                TextField("输入课程名称", text: $draft.name).font(.title2.weight(.semibold))
                Divider()
                HStack {
                    Label("颜色", systemImage: "paintpalette"); Spacer()
                    ColorPicker("颜色", selection: colorBinding, supportsOpacity: false).labelsHidden()
                }
                Divider()
                HStack {
                    Label("学分", systemImage: "star.circle"); Spacer()
                    TextField("选填", text: creditsBinding).multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad).frame(width: 90)
                }
                Divider()
                TextField("备注（所有时段共用）", text: notesBinding, axis: .vertical).lineLimit(2...5)
            }
        }
    }

    private var adjustmentHistory: some View {
        KebiaoCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("临时调整记录").font(.headline)
                Text("恢复后需点击保存；取消编辑会保留原来的停课或调课。")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(draft.exceptions) { exception in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exception.action == .cancelled ? "已停课" : "已调课").font(.subheadline.weight(.semibold))
                            Text(exceptionDescription(exception)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("恢复原安排") { draft.exceptions.removeAll { $0.id == exception.id } }
                            .font(.caption).buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private func exceptionDescription(_ exception: CourseException) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timetable.calendar.timeZone
        formatter.dateFormat = "yyyy/M/d HH:mm"
        let original: String
        switch exception.source {
        case .weekly(let day): original = day
        case .dated(let eventID):
            original = draft.timeSlots.flatMap { $0.datedEvents ?? [] }.first { $0.id == eventID }
                .map { formatter.string(from: $0.startDate) } ?? "具体日期课程"
        }
        if let date = exception.startDate, exception.action == .replaced {
            return "原安排：" + original + " → " + formatter.string(from: date)
        }
        return "原安排：" + original
    }
    private var managementButtons: some View {
        HStack(spacing: 12) {
            Button { if store.duplicate(draft, into: timetable.id) { dismiss() } else { saveError = store.errorMessage } } label: {
                Label("复制课程", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
            }.buttonStyle(.bordered)
            Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                Label("删除", systemImage: "trash").frame(maxWidth: .infinity)
            }.buttonStyle(.bordered)
        }.buttonBorderShape(.roundedRectangle(radius: 14))
    }

    private func slotBinding(id: UUID) -> Binding<CourseTimeSlot> {
        Binding(get: { draft.timeSlots.first { $0.id == id } ?? draft.timeSlots[0] }, set: { value in
            if let index = draft.timeSlots.firstIndex(where: { $0.id == id }) {
                draft.timeSlots[index] = value
                draft.exceptions.removeAll { exception in
                    guard exception.slotID == id else { return false }
                    switch exception.source {
                    case .weekly: return value.datedEvents != nil
                    case .dated(let eventID): return value.datedEvents?.contains { $0.id == eventID } != true
                    }
                }
            }
        })
    }

    private func duplicateSlot(_ slot: CourseTimeSlot) {
        var copy = slot
        copy.id = UUID()
        copy.datedEvents = slot.datedEvents?.map { event in var copy = event; copy.id = UUID(); return copy }
        draft.timeSlots.append(copy)
    }

    private var creditsBinding: Binding<String> {
        Binding(get: { draft.credits.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? "" },
            set: { draft.credits = Double($0.replacingOccurrences(of: ",", with: ".")) })
    }
    private var notesBinding: Binding<String> {
        Binding(get: { draft.notes ?? "" }, set: { draft.notes = $0.isEmpty ? nil : $0 })
    }
    private var colorBinding: Binding<Color> {
        Binding(get: { draft.color }, set: { draft.colorValue = $0.courseHexValue ?? draft.colorValue })
    }
}

private enum CourseSheet: Identifiable {
    case create, edit(Course), importSchedule
    var id: String {
        switch self {
        case .create: "create"
        case .edit(let course): course.id.uuidString
        case .importSchedule: "import"
        }
    }
}

private extension Color {
    var courseHexValue: Int? {
        guard let components = UIColor(self).cgColor.components else { return nil }
        let values = components.count == 2 ? [components[0], components[0], components[0]] : components
        guard values.count >= 3 else { return nil }
        return (Int(values[0] * 255) << 16) | (Int(values[1] * 255) << 8) | Int(values[2] * 255)
    }
}
