import SwiftUI

struct ScheduleView: View {
    let store: TimetableStore
    @State private var selectedDay = Weekday.today

    private var dayCourses: [Course] { store.courses(on: selectedDay) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                dayPicker
                schedule
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarHidden(true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("我的课表")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text(todayText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 20)
    }

    private var dayPicker: some View {
        HStack(spacing: 8) {
            ForEach(Weekday.allCases) { day in
                Button {
                    selectedDay = day
                } label: {
                    VStack(spacing: 4) {
                        Text(day.shortName)
                            .font(.caption.weight(.semibold))
                        Text("\(dayNumber(for: day))")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .foregroundStyle(day == selectedDay ? .white : .primary)
                    .background(day == selectedDay ? Color.indigo : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                }
                .accessibilityLabel(day.fullName)
            }
        }
    }

    @ViewBuilder
    private var schedule: some View {
        if dayCourses.isEmpty {
            ContentUnavailableView("今天没有课程", systemImage: "sun.max", description: Text("享受属于自己的时间吧。"))
                .frame(maxWidth: .infinity, minHeight: 340)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(dayCourses) { course in
                    CourseCard(course: course)
                }
            }
        }
    }

    private var todayText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: .now)
    }

    private func dayNumber(for day: Weekday) -> Int {
        let calendar = Calendar.current
        return calendar.component(.day, from: ScheduleEngine.date(for: day, inWeekContaining: .now, calendar: calendar))
    }
}

private struct CourseCard: View {
    let course: Course

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(course.startSection)\n—\n\(course.endSection)")
                .font(.caption.weight(.bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(course.color)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 8) {
                Text(course.name).font(.title3.weight(.bold))
                Label(course.location, systemImage: "mappin.and.ellipse")
                Label(course.teacher, systemImage: "person")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(course.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 22))
        .overlay(alignment: .leading) {
            Capsule().fill(course.color).frame(width: 5).padding(.vertical, 14)
        }
    }
}
