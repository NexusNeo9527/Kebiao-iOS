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
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry(for: now)], policy: .after(tomorrow)))
    }

    private func entry(for date: Date) -> TodayEntry {
        let defaults = UserDefaults(suiteName: "group.com.example.kebiao") ?? .standard
        let courses = defaults.data(forKey: "kebiao.courses.v1")
            .flatMap { try? JSONDecoder().decode([Course].self, from: $0) } ?? []
        let weekday = Weekday(rawValue: Calendar.current.component(.weekday, from: date)) ?? .monday
        return TodayEntry(date: date, courses: courses.filter { $0.weekdays.contains(weekday) }.sorted { $0.startSection < $1.startSection })
    }
}

struct KebiaoTodayWidget: Widget {
    let kind = "KebiaoTodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.indigo.opacity(0.10) }
        }
        .configurationDisplayName("今日课表")
        .description("快速查看今天的课程安排。")
        .supportedFamilies([.systemSmall, .systemMedium])
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
                Text("好好休息，或预习下一门课。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(entry.courses.prefix(family == .systemSmall ? 2 : 4)) { course in
                    HStack(spacing: 8) {
                        Circle().fill(course.color).frame(width: 8, height: 8)
                        Text("第\(course.startSection)节")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(course.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
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
        .widgetURL(URL(string: "kebiao://schedule"))
    }
}
