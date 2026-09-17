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
    @State private var weekAnchor = Date.now
    @State private var selectedCourse: Course?
    @State private var weekDirection = 1
    @GestureState private var dragOffset: CGFloat = 0

    private let timeColumnWidth: CGFloat = 46
    private let sectionHeight: CGFloat = 76

    private var calendar: Calendar { .current }
    private var sectionCount: Int {
        max(10, store.courses.map(\.endSection).max() ?? 10)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                VStack(spacing: 0) {
                    weekdayHeader
                    timetable
                }
                .id(weekPageID)
                .offset(x: dragOffset)
                .transition(weekTransition)
            }
            .clipped()
        }
        .background(KebiaoTheme.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .sheet(item: $selectedCourse) { course in
            CourseDetailSheet(course: course)
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
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(day.fullName)，\(calendar.component(.day, from: date))日")
            }
        }
        .padding(.bottom, 8)
    }

    private var timetable: some View {
        ScrollView(.vertical, showsIndicators: false) {
            GeometryReader { geometry in
                let dayWidth = (geometry.size.width - timeColumnWidth) / CGFloat(Weekday.allCases.count)

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
        .simultaneousGesture(weekSwipeGesture)
    }

    private var weekSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .updating($dragOffset) { value, state, _ in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = value.translation.width * 0.72
            }
            .onEnded { value in
                guard let delta = WeekSwipeDecision.weekDelta(
                    translation: value.translation,
                    predictedEndTranslation: value.predictedEndTranslation
                ) else { return }
                moveWeek(by: delta)
            }
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
            }
        }
    }

    private func courseBlocks(dayWidth: CGFloat) -> some View {
        ForEach(store.courses.filter { $0.isActive(academicWeek: weekNumber) }) { course in
            ForEach(course.weekdays.sorted(by: { $0.weekIndex < $1.weekIndex })) { day in
                Button {
                    selectedCourse = course
                } label: {
                    CourseBlock(course: course)
                }
                .buttonStyle(.plain)
                .frame(
                    width: max(0, dayWidth - 6),
                    height: CGFloat(course.sectionCount) * sectionHeight - 6
                )
                .offset(
                    x: timeColumnWidth + CGFloat(day.weekIndex) * dayWidth + 3,
                    y: CGFloat(course.startSection - 1) * sectionHeight + 3
                )
                .accessibilityLabel(
                    "\(course.name)，\(day.fullName)，第\(course.startSection)到第\(course.endSection)节"
                )
                .accessibilityHint("轻点查看课程详情")
            }
        }
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
        ScheduleEngine.academicWeekNumber(for: weekAnchor, calendar: calendar)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(course.name)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(3)

            Text("@ \(course.location)")
                .font(.system(size: 10, weight: .medium))
                .lineLimit(3)

            Spacer(minLength: 0)

            Text("\(course.startSection)–\(course.endSection)节")
                .font(.system(size: 9, weight: .bold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(course.color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.7), lineWidth: 2)
        }
        .shadow(color: course.color.opacity(0.24), radius: 4, y: 2)
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
        let duration = max(45, course.sectionCount * 45 + max(0, course.sectionCount - 1) * 10)
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
