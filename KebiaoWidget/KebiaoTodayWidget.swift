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
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now.addingTimeInterval(86_400)
        let todayCourses = entry(for: now).courses
        let courseBoundaries = todayCourses.flatMap { course -> [Date] in
            let start = calendar.date(
                byAdding: .minute,
                value: course.resolvedStartTimeMinutes,
                to: startOfToday
            ) ?? now
            let duration = max(45, course.sectionCount * 45 + max(0, course.sectionCount - 1) * 10)
            let end = calendar.date(byAdding: .minute, value: duration, to: start) ?? start
            return [start, end]
        }
        let refreshDates = Array(Set([now] + courseBoundaries + [tomorrow]))
            .filter { $0 >= now }
            .sorted()
        let entries = refreshDates.map { entry(for: $0) }
        completion(Timeline(entries: entries, policy: .after(tomorrow)))
    }

    private func entry(for date: Date) -> TodayEntry {
        let defaults = UserDefaults(suiteName: KebiaoConfiguration.appGroupIdentifier) ?? .standard
        let courses = defaults.data(forKey: KebiaoConfiguration.storageKey)
            .flatMap { try? JSONDecoder().decode([Course].self, from: $0) } ?? []
        let weekday = Weekday.from(calendarWeekday: Calendar.current.component(.weekday, from: date))
        return TodayEntry(date: date, courses: courses.filter { $0.weekdays.contains(weekday) }.sorted { $0.startSection < $1.startSection })
    }
}

struct KebiaoTodayWidget: Widget {
    let kind = KebiaoConfiguration.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
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

    private var visibleCourses: ArraySlice<Course> {
        let sorted = entry.courses.sorted {
            distanceFromNow(to: $0) < distanceFromNow(to: $1)
        }
        return sorted.prefix(family == .systemSmall ? 2 : 4)
    }

    private func distanceFromNow(to course: Course) -> Int {
        let nowMinutes = Calendar.current.component(.hour, from: entry.date) * 60
            + Calendar.current.component(.minute, from: entry.date)
        return abs(course.resolvedStartTimeMinutes - nowMinutes)
    }

    private func courseStatus(_ course: Course) -> String {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: entry.date)
        let start = calendar.date(
            byAdding: .minute,
            value: course.resolvedStartTimeMinutes,
            to: startOfDay
        ) ?? entry.date
        let duration = max(45, course.sectionCount * 45 + max(0, course.sectionCount - 1) * 10)
        let end = calendar.date(byAdding: .minute, value: duration, to: start) ?? start

        if entry.date >= start && entry.date < end {
            return "进行中 · 第\(course.startSection)–\(course.endSection)节"
        }
        return "\(start.formatted(date: .omitted, time: .shortened)) · 第\(course.startSection)–\(course.endSection)节"
    }
}
