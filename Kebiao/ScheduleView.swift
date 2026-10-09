import SwiftUI

enum WeekSwipeDecision {
    static func weekDelta(
        translation: CGSize,
        predictedEndTranslation: CGSize,
        minimumDistance: CGFloat = 60
    ) -> Int? {
        let horizontal = translation.width
        let vertical = translation.height
        let projectedDistance = max(abs(horizontal), abs(predictedEndTranslation.width))
        guard projectedDistance >= minimumDistance,
              abs(horizontal) > abs(vertical) * 1.2 else {
            return nil
        }
        return horizontal < 0 ? 1 : -1
    }
}

struct ScheduleView: View {
    let store: TimetableStore
    private let previewCourses: [Course]?
    private let showsNavigationBar: Bool
    @State private var weekAnchor = Date.now
    @State private var selectedGroup: TimetableCourseGroup?
    @State private var weekDirection = 1

    private let timeColumnWidth: CGFloat = 46
    private let sectionHeight: CGFloat = 76

    init(store: TimetableStore, courses: [Course]? = nil, initialDate: Date = .now,
         showsNavigationBar: Bool = false) {
        self.store = store
        self.previewCourses = courses
        self.showsNavigationBar = showsNavigationBar
        _weekAnchor = State(initialValue: initialDate)
    }

    private var calendar: Calendar { .current }
    private var courses: [Course] { previewCourses ?? store.courses }
    private var sectionCount: Int {
        max(10, courses.map(\.endSection).max() ?? 10)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                GeometryReader { geometry in
                    let dayWidth = max(96, (geometry.size.width - timeColumnWidth) / 7)
                    ScrollView(.horizontal, showsIndicators: true) {
                        ScrollViewReader { scrollProxy in
                        VStack(spacing: 0) {
                            weekdayHeader
                            timetable(dayWidth: dayWidth)
                        }
                        .frame(width: timeColumnWidth + dayWidth * 7)
                        .onAppear {
                            if showsNavigationBar {
                                scrollProxy.scrollTo("day-\(firstVisibleDay.rawValue)", anchor: .center)
                            }
                        }
                        }
                    }
                }
                .id(weekPageID)
                .transition(weekTransition)
            }
            .clipped()
        }
        .background(KebiaoTheme.background.ignoresSafeArea())
        .navigationBarHidden(!showsNavigationBar)
        .sheet(item: $selectedGroup) { group in
            GroupCourseSheet(group: group)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("第 \(weekNumber) 周")
                    .font(.title2.weight(.bold))
                Text(weekRangeText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                headerButton(systemImage: "chevron.left", accessibilityLabel: "上一周") {
                    moveWeek(by: -1)
                }
                Button("今天") {
                    weekDirection = Date.now >= weekAnchor ? 1 : -1
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { weekAnchor = .now }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                headerButton(systemImage: "chevron.right", accessibilityLabel: "下一周") {
                    moveWeek(by: 1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            Text("节")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: timeColumnWidth)

            ForEach(Weekday.allCases) { day in
                let date = day.date(inWeekContaining: weekAnchor, calendar: calendar)
                VStack(spacing: 3) {
                    Text(day.shortName.replacingOccurrences(of: "周", with: ""))
                        .font(.caption.weight(.semibold))
                    Text(date, format: .dateTime.day())
                        .font(.subheadline.weight(isToday(date) ? .bold : .regular))
                        .frame(width: 28, height: 28)
                        .background(isToday(date) ? Color.primary : .clear, in: Circle())
                        .foregroundStyle(isToday(date) ? .white : .secondary)
                }
                .frame(maxWidth: .infinity)
                .id("day-\(day.rawValue)")
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(day.fullName)，\(calendar.component(.day, from: date))日")
            }
        }
        .padding(.bottom, 8)
    }

    private func timetable(dayWidth: CGFloat) -> some View {
        ScrollViewReader { scrollProxy in
        ScrollView(.vertical, showsIndicators: false) {
            GeometryReader { _ in
                ZStack(alignment: .topLeading) {
                    gridLines(dayWidth: dayWidth)
                    sectionLabels
                    courseBlocks(dayWidth: dayWidth)
                }
                .frame(height: CGFloat(sectionCount) * sectionHeight)
            }
            .frame(height: CGFloat(sectionCount) * sectionHeight)
            .padding(.bottom, 24)
        }
        .contentShape(Rectangle())
        .onAppear {
            if showsNavigationBar {
                scrollProxy.scrollTo("section-\(firstVisibleSection)", anchor: .top)
            }
        }
        }
    }

    private var firstVisibleDay: Weekday {
        Weekday.allCases.first { day in
            courses.contains {
                !ScheduleEngine.occurrences(for: $0, on: day.date(inWeekContaining: weekAnchor),
                                             semesterStart: store.semesterStartDate).isEmpty
            }
        } ?? .monday
    }

    private var firstVisibleSection: Int {
        courses.filter {
            !ScheduleEngine.occurrences(for: $0, on: firstVisibleDay.date(inWeekContaining: weekAnchor),
                                         semesterStart: store.semesterStartDate).isEmpty
        }.map(\.startSection).min() ?? 1
    }

    private func gridLines(dayWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0...sectionCount, id: \.self) { row in
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: dayWidth * CGFloat(Weekday.allCases.count), height: 0.5)
                    .offset(x: timeColumnWidth, y: CGFloat(row) * sectionHeight)
            }

            ForEach(0...Weekday.allCases.count, id: \.self) { column in
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 0.5, height: CGFloat(sectionCount) * sectionHeight)
                    .offset(x: timeColumnWidth + CGFloat(column) * dayWidth)
            }
        }
    }

    private var sectionLabels: some View {
        VStack(spacing: 0) {
            ForEach(1...sectionCount, id: \.self) { section in
                VStack(spacing: 3) {
                    Text("\(section)")
                        .font(.headline)
                    Text(timeText(for: section))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 6)
                .frame(width: timeColumnWidth, height: sectionHeight, alignment: .top)
                .id("section-\(section)")
            }
        }
    }

    private func courseBlocks(dayWidth: CGFloat) -> some View {
        ForEach(Weekday.allCases) { day in
            ForEach(courseGroups(on: day)) { group in
                Button {
                    selectedGroup = group
                } label: {
                    if group.courses.count == 1, let course = group.courses.first {
                        CourseBlock(course: course)
                    } else {
                        OverlappingCoursesBlock(group: group)
                    }
                }
                .buttonStyle(.plain)
                .frame(
                    width: dayWidth - 6,
                    height: CGFloat(group.endSection - group.startSection + 1) * sectionHeight - 6
                )
                .offset(
                    x: timeColumnWidth
                        + CGFloat(day.weekIndex) * dayWidth
                        + 3,
                    y: CGFloat(group.startSection - 1) * sectionHeight + 3
                )
                .accessibilityLabel(
                    group.courses.map(\.name).joined(separator: "、")
                )
                .accessibilityHint(group.courses.count > 1 ? "轻点查看全部重叠课程" : "轻点查看课程详情")
            }
        }
    }

    private func courseGroups(on day: Weekday) -> [TimetableCourseGroup] {
        TimetableCourseGroup.groups(courses.filter {
            !ScheduleEngine.occurrences(for: $0, on: day.date(inWeekContaining: weekAnchor),
                                        semesterStart: store.semesterStartDate).isEmpty
        })
    }

    private func headerButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var weekNumber: Int {
        return ScheduleEngine.academicWeekNumber(for: weekAnchor, calendar: calendar,
                                                  semesterStart: store.semesterStartDate)
    }

    private var weekRangeText: String {
        let start = Weekday.monday.date(inWeekContaining: weekAnchor, calendar: calendar)
        let end = Weekday.sunday.date(inWeekContaining: weekAnchor, calendar: calendar)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy/M/d"
        return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
    }

    private func timeText(for section: Int) -> String {
        let minutes = SectionSchedule.startMinutes(for: section)
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }

    private func moveWeek(by value: Int) {
        weekDirection = value >= 0 ? 1 : -1
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            weekAnchor = calendar.date(byAdding: .weekOfYear, value: value, to: weekAnchor) ?? weekAnchor
        }
    }

    private var weekPageID: Date {
        Weekday.monday.date(inWeekContaining: weekAnchor, calendar: calendar)
    }

    private var weekTransition: AnyTransition {
        let insertion: Edge = weekDirection > 0 ? .trailing : .leading
        let removal: Edge = weekDirection > 0 ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertion).combined(with: .opacity),
            removal: .move(edge: removal).combined(with: .opacity)
        )
    }
}

private struct CourseBlock: View {
    let course: Course
    var isNarrow = false

    private var isCompact: Bool { isNarrow || course.sectionCount == 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(course.name)
                .font(.system(size: isCompact ? 12 : 13, weight: .bold))
                .lineLimit(isCompact ? 4 : 3)
                .layoutPriority(1)

            if !isCompact {
                Text(course.location.isEmpty ? "未填写地点" : "@ \(course.location)")
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(2)
                    .layoutPriority(0)

                Spacer(minLength: 0)

                Text("\(course.startSection)–\(course.endSection)节")
                    .font(.system(size: 9, weight: .bold))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .padding(isCompact ? 4 : 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(course.color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.7), lineWidth: 2)
        }
        .shadow(color: course.color.opacity(0.24), radius: 4, y: 2)
    }
}

struct TimetableCourseGroup: Identifiable {
    let courses: [Course]
    var id: UUID { courses[0].id }
    var startSection: Int { courses.map(\.startSection).min() ?? 1 }
    var endSection: Int { courses.map(\.endSection).max() ?? 1 }

    static func groups(_ courses: [Course]) -> [Self] {
        let sorted = courses.sorted {
            if $0.startSection != $1.startSection { return $0.startSection < $1.startSection }
            if $0.endSection != $1.endSection { return $0.endSection < $1.endSection }
            return $0.id.uuidString < $1.id.uuidString
        }
        var result: [Self] = []
        var pending: [Course] = []
        var end = 0
        for course in sorted {
            if !pending.isEmpty && course.startSection > end {
                result.append(Self(courses: pending))
                pending = []
                end = 0
            }
            pending.append(course)
            end = max(end, course.endSection)
        }
        if !pending.isEmpty { result.append(Self(courses: pending)) }
        return result
    }
}

private struct OverlappingCoursesBlock: View {
    let group: TimetableCourseGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(group.courses.count)门重叠")
                .font(.system(size: 12, weight: .bold))
                .lineLimit(1)
            Text(group.courses.map(\.name).joined(separator: " / "))
                .font(.system(size: 12, weight: .medium))
                .lineLimit(group.endSection == group.startSection ? 1 : 4)
            Spacer(minLength: 0)
            Text("点开查看").font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KebiaoTheme.accent, in: RoundedRectangle(cornerRadius: 10))
        .clipped()
    }
}

private struct GroupCourseSheet: View {
    @Environment(\.dismiss) private var dismiss
    let group: TimetableCourseGroup

    var body: some View {
        if group.courses.count == 1, let course = group.courses.first {
            CourseDetailSheet(course: course)
        } else {
            NavigationStack {
                List {
                    Section {
                        ForEach(group.courses) { course in
                            NavigationLink {
                                CourseDetailSheet(course: course)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(course.name).font(.headline)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text("第\(course.startSection)–\(course.endSection)节 · \(course.location)")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 5)
                            }
                        }
                    } footer: {
                        Text("这些课程的节次有重叠，请核对课程安排；全部课程已保留。")
                    }
                }
                .navigationTitle("\(group.courses.count)门重叠课程")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { dismiss() }
                    }
                }
            }
        }
    }
}

private struct CourseDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let course: Course

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(course.color)
                        .frame(width: 6, height: 40)
                    Text(course.name)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                }

                Divider()
                CourseDetailRow(icon: "calendar", text: weekdayText)
                CourseDetailRow(
                    icon: "clock",
                    text: "第\(course.startSection)–\(course.endSection)节  \(timeRangeText)"
                )
                CourseDetailRow(icon: "mappin.and.ellipse", text: course.location)
                CourseDetailRow(icon: "person", text: course.teacher)
                CourseDetailRow(icon: "bell", text: reminderText)
                Spacer()
            }
            .padding(24)
            .navigationTitle("课程详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var weekdayText: String {
        course.weekdays
            .sorted(by: { $0.weekIndex < $1.weekIndex })
            .map(\.shortName)
            .joined(separator: "、")
    }

    private var timeRangeText: String {
        let start = course.resolvedStartTimeMinutes
        let duration = course.resolvedDurationMinutes
        let end = start + duration
        return String(
            format: "%02d:%02d–%02d:%02d",
            start / 60,
            start % 60,
            end / 60,
            end % 60
        )
    }

    private var reminderText: String {
        course.reminderMinutesBefore.map { "提前 \($0) 分钟提醒" } ?? "未设置提醒"
    }
}

private struct CourseDetailRow: View {
    let icon: String
    let text: String

    var body: some View {
        Label {
            Text(text)
                .font(.body)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 24)
        }
    }
}
