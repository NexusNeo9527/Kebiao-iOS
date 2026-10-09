import SwiftUI

struct DayScheduleView: View {
    let store: TimetableStore
    @State private var selectedDate = Date.now
    @State private var now = Date.now
    @Environment(\.scenePhase) private var scenePhase
    @State private var presentedSheet: DayScheduleSheet?
    @State private var completedExpanded = true

    private var timetable: Timetable { store.activeTimetable }
    private var calendar: Calendar { timetable.calendar }
    private var weekday: Weekday {
        Weekday.from(calendarWeekday: calendar.component(.weekday, from: selectedDate))
    }
    private var occurrences: [CourseOccurrence] {
        ScheduleEngine.occurrences(in: timetable, on: selectedDate)
    }
    private var completed: [CourseOccurrence] { occurrences.filter { $0.endDate <= now } }
    private var upcoming: [CourseOccurrence] { occurrences.filter { $0.endDate > now } }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            KebiaoTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    dateHeader

                    if calendar.isDate(selectedDate, inSameDayAs: now), let next = upcoming.first {
                        nextCourseCard(next)
                    }

                    if !completed.isEmpty {
                        completedSection
                    }

                    if upcoming.isEmpty, completed.isEmpty {
                        ContentUnavailableView(
                            "当天没有课程",
                            systemImage: "calendar.badge.checkmark",
                            description: Text("轻点右下角添加课程，或到课程页导入学校课表。")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                    } else {
                        ForEach(upcoming) { course in
                            courseButton(course)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 110)
            }

            Button {
                presentedSheet = .create
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(KebiaoTheme.accent)
                    .frame(width: 64, height: 64)
                    .background(.white, in: Circle())
                    .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
            }
            .accessibilityLabel("添加课程")
            .padding(.trailing, 24)
            .padding(.bottom, 28)
        }
        .navigationBarHidden(true)
        .task {
            while !Task.isCancelled {
                now = .now
                try? await Task.sleep(for: .seconds(15))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { now = .now }
        }
        .onChange(of: store.activeTimetableID) { _, _ in presentedSheet = nil }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .create: CourseEditorView(course: nil, store: store)
            case .edit(let course): CourseEditorView(course: course, store: store)
            case .adjust(let occurrence): OccurrenceAdjustmentView(store: store, occurrence: occurrence)
            case .occurrence(let occurrence): occurrenceDetails(occurrence)
            }
        }
    }

    private var dateHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(dateTitle)
                    .font(.title2.weight(.bold))
                Text("\(timetable.name) · \(weekday.fullName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            HStack(spacing: 8) {
                dateButton("chevron.left", label: "前一天") { moveDay(-1) }
                Button("今天") { withAnimation(.smooth) { selectedDate = .now } }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KebiaoTheme.accent)
                dateButton("chevron.right", label: "后一天") { moveDay(1) }
            }
        }
    }

    private func nextCourseCard(_ occurrence: CourseOccurrence) -> some View {
        KebiaoCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(occurrence.startDate <= now ? "正在上课" : "下一节课", systemImage: "clock.badge")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(KebiaoTheme.accent)
                    Spacer()
                    Text(timeRange(occurrence))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(occurrence.course.name)
                    .font(.title3.weight(.bold))
                Label(locationText(occurrence), systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var completedSection: some View {
        VStack(spacing: 10) {
            Button {
                withAnimation(.snappy) { completedExpanded.toggle() }
            } label: {
                HStack {
                    Text("已完成（\(completed.count)）")
                        .font(.headline)
                    Spacer()
                    Image(systemName: completedExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .padding(18)
                .background(.white, in: RoundedRectangle(cornerRadius: KebiaoTheme.cardRadius, style: .continuous))
            }
            .buttonStyle(.plain)

            if completedExpanded {
                ForEach(completed) { course in courseButton(course) }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func courseButton(_ occurrence: CourseOccurrence) -> some View {
        Button { presentedSheet = .occurrence(occurrence) } label: {
            HStack(spacing: 16) {
                VStack(alignment: .trailing, spacing: 6) {
                    Text(timeText(occurrence.startDate))
                    Text(endTimeText(occurrence))
                }
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: calendar.isDate(occurrence.startDate, inSameDayAs: occurrence.endDate) ? 48 : 80)

                Capsule()
                    .fill(occurrence.course.color)
                    .frame(width: 6, height: 62)

                VStack(alignment: .leading, spacing: 8) {
                    Text(occurrence.course.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Label(locationText(occurrence), systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text("课程")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(KebiaoTheme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(KebiaoTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(18)
            .background(.white, in: RoundedRectangle(cornerRadius: KebiaoTheme.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("轻点查看本次课程，编辑课程或调整本次安排")
    }

    private func dateButton(_ image: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image).frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func moveDay(_ value: Int) {
        withAnimation(.snappy) {
            selectedDate = calendar.date(byAdding: .day, value: value, to: selectedDate) ?? selectedDate
        }
    }

    private func occurrenceDetails(_ occurrence: CourseOccurrence) -> some View {
        NavigationStack {
            Form {
                Section("本次课程") {
                    LabeledContent("课程", value: occurrence.course.name)
                    LabeledContent("日期", value: formatted(occurrence.startDate, pattern: "yyyy/M/d"))
                    LabeledContent("时间", value: timeRange(occurrence))
                    LabeledContent("教师", value: occurrence.teacher.isEmpty ? "未填写" : occurrence.teacher)
                    LabeledContent("教室", value: locationText(occurrence))
                }
                if let course = store.timetable(id: occurrence.timetableID)?.courses.first(where: { $0.id == occurrence.courseID }) {
                    Section("全部上课周次") {
                        ForEach(Array(course.timeSlots.enumerated()), id: \.element.id) { index, slot in
                            LabeledContent("时段 \(index + 1)", value: CourseScheduleText.weeks(for: slot))
                        }
                    }
                    if course.credits != nil || course.notes?.isEmpty == false {
                        Section("课程资料") {
                            if let credits = course.credits { LabeledContent("学分", value: credits.formatted()) }
                            if let notes = course.notes, !notes.isEmpty { LabeledContent("备注", value: notes) }
                        }
                    }
                }
                Section {
                    Button("仅调整本次安排") { presentedSheet = .adjust(occurrence) }
                    Button("编辑整门课程") {
                        if let course = timetable.courses.first(where: { $0.id == occurrence.courseID }) {
                            presentedSheet = .edit(course)
                        }
                    }
                } footer: {
                    Text("调整本次仅影响这个日期；编辑整门课程会修改其全部上课安排。")
                }
            }
            .navigationTitle("课程详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { presentedSheet = nil } }
            }
        }
    }

    private func locationText(_ occurrence: CourseOccurrence) -> String {
        occurrence.location.isEmpty ? "暂未填写教室" : occurrence.location
    }
    private func timeRange(_ occurrence: CourseOccurrence) -> String { "\(timeText(occurrence.startDate))–\(endTimeText(occurrence))" }
    private func endTimeText(_ occurrence: CourseOccurrence) -> String {
        let pattern = calendar.isDate(occurrence.startDate, inSameDayAs: occurrence.endDate) ? "HH:mm" : "M/d HH:mm"
        return formatted(occurrence.endDate, pattern: pattern)
    }
    private func timeText(_ date: Date) -> String { formatted(date, pattern: "HH:mm") }
    private var dateTitle: String { formatted(selectedDate, pattern: "yyyy/M/d") }
    private func formatted(_ date: Date, pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

private enum DayScheduleSheet: Identifiable {
    case create, occurrence(CourseOccurrence), edit(Course), adjust(CourseOccurrence)
    var id: String {
        switch self {
        case .create: "create"
        case .occurrence(let occurrence): "occurrence-\(occurrence.id)"
        case .edit(let course): "edit-\(course.id)"
        case .adjust(let occurrence): "adjust-\(occurrence.id)"
        }
    }
}
