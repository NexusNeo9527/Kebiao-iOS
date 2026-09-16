import SwiftUI

struct DayScheduleView: View {
    let store: TimetableStore
    @State private var selectedDate = Date.now
    @State private var presentedCourse: Course?
    @State private var creatingCourse = false
    @State private var completedExpanded = true

    private var weekday: Weekday {
        Weekday.from(calendarWeekday: Calendar.current.component(.weekday, from: selectedDate))
    }

    private var courses: [Course] {
        let week = ScheduleEngine.academicWeekNumber(for: selectedDate)
        return store.courses(on: weekday).filter { $0.isActive(academicWeek: week) }
    }
    private var completed: [Course] { courses.filter { endDate(for: $0) < .now && Calendar.current.isDateInToday(selectedDate) } }
    private var upcoming: [Course] { courses.filter { !completed.contains($0) } }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            KebiaoTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    dateHeader

                    if Calendar.current.isDateInToday(selectedDate), let next = upcoming.first {
                        nextCourseCard(next)
                    }

                    if !completed.isEmpty {
                        completedSection
                    }

                    if upcoming.isEmpty, completed.isEmpty {
                        ContentUnavailableView(
                            "今天没有课程",
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
                creatingCourse = true
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
        .sheet(isPresented: $creatingCourse) {
            CourseEditorView(course: nil, store: store)
        }
        .sheet(item: $presentedCourse) { course in
            CourseEditorView(course: course, store: store)
        }
    }

    private var dateHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(dateTitle)
                    .font(.title2.weight(.bold))
                Text(weekday.fullName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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

    private func nextCourseCard(_ course: Course) -> some View {
        KebiaoCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("下一节课", systemImage: "clock.badge")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(KebiaoTheme.accent)
                    Spacer()
                    Text(timeRange(course))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(course.name)
                    .font(.title3.weight(.bold))
                Label(course.location.isEmpty ? "暂未填写教室" : course.location, systemImage: "mappin.and.ellipse")
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

    private func courseButton(_ course: Course) -> some View {
        Button { presentedCourse = course } label: {
            HStack(spacing: 16) {
                VStack(alignment: .trailing, spacing: 6) {
                    Text(startText(course))
                    Text(endText(course))
                }
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48)

                Capsule()
                    .fill(course.color)
                    .frame(width: 6, height: 62)

                VStack(alignment: .leading, spacing: 8) {
                    Text(course.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Label(course.location.isEmpty ? "暂未填写教室" : course.location, systemImage: "mappin.and.ellipse")
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
        .accessibilityHint("轻点查看并编辑课程详情")
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
            selectedDate = Calendar.current.date(byAdding: .day, value: value, to: selectedDate) ?? selectedDate
        }
    }

    private func startText(_ course: Course) -> String { minuteText(course.resolvedStartTimeMinutes) }
    private func endText(_ course: Course) -> String {
        let duration = max(45, course.sectionCount * 45 + max(0, course.sectionCount - 1) * 10)
        return minuteText(course.resolvedStartTimeMinutes + duration)
    }
    private func timeRange(_ course: Course) -> String { "\(startText(course))–\(endText(course))" }
    private func minuteText(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }
    private func endDate(for course: Course) -> Date {
        let start = Calendar.current.startOfDay(for: selectedDate)
        let duration = max(45, course.sectionCount * 45 + max(0, course.sectionCount - 1) * 10)
        return Calendar.current.date(byAdding: .minute, value: course.resolvedStartTimeMinutes + duration, to: start) ?? start
    }

    private var dateTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy/M/d"
        return formatter.string(from: selectedDate)
    }
}
