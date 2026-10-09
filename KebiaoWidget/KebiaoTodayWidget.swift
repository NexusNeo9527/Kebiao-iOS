import SwiftUI
import WidgetKit

struct TodayEntry: TimelineEntry {
    let date: Date
    let courses: [Course]
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, courses: Array(Course.samples.prefix(2)))
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(entry(for: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)
            ?? now.addingTimeInterval(86_400)
        let todayCourses = entry(for: now).courses
        let courseBoundaries = todayCourses.flatMap { course -> [Date] in
            let start = calendar.date(
                byAdding: .minute,
                value: course.resolvedStartTimeMinutes,
                to: startOfToday
            ) ?? now
            let duration = course.resolvedDurationMinutes
            let end = calendar.date(byAdding: .minute, value: duration, to: start) ?? start
            return [start, end]
        }
        let refreshDates = Array(Set([now, tomorrow] + courseBoundaries)
            .filter { $0 >= now }
            .sorted())
        completion(Timeline(entries: refreshDates.map { entry(for: $0) }, policy: .after(tomorrow)))
    }

    private func entry(for date: Date) -> TodayEntry {
        let defaults = UserDefaults(suiteName: KebiaoConfiguration.appGroupIdentifier)
        let courses = defaults?.data(forKey: KebiaoConfiguration.storageKey)
            .flatMap { try? JSONDecoder().decode([Course].self, from: $0) } ?? []
        let activeCourses = ScheduleEngine.courses(in: courses, on: date)
        return TodayEntry(date: date, courses: activeCourses.sorted {
            $0.resolvedStartTimeMinutes < $1.resolvedStartTimeMinutes
        })
    }
}

struct KebiaoTodayWidget: Widget {
    let kind = KebiaoConfiguration.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .environment(\.colorScheme, .light)
                .containerBackground(for: .widget) { Color.indigo.opacity(0.10) }
        }
        .configurationDisplayName("今日课表")
        .description("快速查看今天的课程安排。")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

private struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("今日课表", systemImage: "calendar")
                    .font(.headline)
                Spacer()
                Text(entry.date, format: .dateTime.weekday(.wide))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if entry.courses.isEmpty {
                Spacer()
                Text("今天没有课程")
                    .font(.title3.weight(.semibold))
                Text("打开课表即可同步最新安排")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(visibleCourses) { course in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(course.color)
                            .frame(width: 4, height: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(course.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(courseStatus(course))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if family == .systemMedium {
                            Text(course.location)
                                .font(.caption)
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding()
        .widgetURL(KebiaoConfiguration.scheduleURL)
    }

    private var visibleCourses: [Course] {
        let sorted = entry.courses.sorted { lhs, rhs in
            let lhsStart = startDate(for: lhs)
            let rhsStart = startDate(for: rhs)
            let lhsIsCurrent = entry.date >= lhsStart && entry.date < endDate(for: lhs)
            let rhsIsCurrent = entry.date >= rhsStart && entry.date < endDate(for: rhs)
            if lhsIsCurrent != rhsIsCurrent { return lhsIsCurrent }

            let lhsIsUpcoming = lhsStart >= entry.date
            let rhsIsUpcoming = rhsStart >= entry.date
            if lhsIsUpcoming != rhsIsUpcoming { return lhsIsUpcoming }
            return lhsIsUpcoming ? lhsStart < rhsStart : lhsStart > rhsStart
        }
        return Array(sorted.prefix(family == .systemSmall ? 2 : 4))
    }

    private func startDate(for course: Course) -> Date {
        Calendar.current.date(
            byAdding: .minute,
            value: course.resolvedStartTimeMinutes,
            to: Calendar.current.startOfDay(for: entry.date)
        ) ?? entry.date
    }

    private func endDate(for course: Course) -> Date {
        let duration = course.resolvedDurationMinutes
        return Calendar.current.date(byAdding: .minute, value: duration, to: startDate(for: course))
            ?? startDate(for: course)
    }

    private func courseStatus(_ course: Course) -> String {
        let start = startDate(for: course)
        if entry.date >= start && entry.date < endDate(for: course) {
            return "进行中 · 第\(course.startSection)–\(course.endSection)节"
        }
        return "\(start.formatted(date: .omitted, time: .shortened)) · 第\(course.startSection)–\(course.endSection)节"
    }
}
