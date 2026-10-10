import SwiftUI
import WidgetKit

struct TodayEntry: TimelineEntry {
    let content: TodayWidgetContentEntry
    var date: Date { content.date }
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        let now = Date.now
        let courses = Course.samples.prefix(2).enumerated().map { index, course in
            let start = now.addingTimeInterval(Double((index + 1) * 3600))
            let event = DatedCourseEvent(startDate: start, endDate: start.addingTimeInterval(Double(course.resolvedDurationMinutes * 60)))
            return Course(name: course.name, colorValue: course.colorValue,
                timeSlots: [CourseTimeSlot(location: course.location, datedEvents: [event])])
        }
        let table = Timetable(name: "示例课表", courses: courses)
        let snapshot = SharedTimetableSnapshot(state: .ready, collection: TimetableCollection(timetables: [table]))
        return entry(for: now, snapshot: snapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(entry(for: .now, snapshot: SharedTimetableReader.shared().read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        let snapshot = SharedTimetableReader.shared().read()
        let calendar = snapshot.timetable?.calendar ?? Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)
            ?? now.addingTimeInterval(86_400)
        let courseBoundaries = entry(for: now, snapshot: snapshot).content.occurrences.flatMap { [$0.startDate, $0.endDate] }
        let refreshDates = Array(Set([now, tomorrow] + courseBoundaries)
            .filter { $0 >= now }
            .sorted())
        completion(Timeline(entries: refreshDates.map { entry(for: $0, snapshot: snapshot) }, policy: .after(tomorrow)))
    }

    private func entry(for date: Date, snapshot: SharedTimetableSnapshot) -> TodayEntry {
        TodayEntry(content: TodayWidgetContentEntry(date: date, snapshot: snapshot))
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
        TodayWidgetContent(entry: entry.content, family: family == .systemSmall ? .small : .medium)
        .widgetURL(KebiaoConfiguration.scheduleURL)
    }
}
