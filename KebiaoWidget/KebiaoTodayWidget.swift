import SwiftUI
import WidgetKit

struct TodayEntry: TimelineEntry {
    let date: Date
    let timetableName: String
    let timeZoneIdentifier: String
    let occurrences: [CourseOccurrence]

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        calendar.firstWeekday = 2
        return calendar
    }
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        let now = Date.now
        let occurrences = Course.samples.prefix(2).enumerated().map { index, course in
            let start = now.addingTimeInterval(Double((index + 1) * 3600))
            return CourseOccurrence(course: course, startDate: start,
                endDate: start.addingTimeInterval(Double(course.resolvedDurationMinutes * 60)))
        }
        return TodayEntry(date: now, timetableName: "示例课表", timeZoneIdentifier: TimeZone.current.identifier,
            occurrences: occurrences)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(entry(for: .now, timetable: loadTimetable()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        let timetable = loadTimetable()
        let calendar = timetable?.calendar ?? Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)
            ?? now.addingTimeInterval(86_400)
        let courseBoundaries = entry(for: now, timetable: timetable).occurrences.flatMap { [$0.startDate, $0.endDate] }
        let refreshDates = Array(Set([now, tomorrow] + courseBoundaries)
            .filter { $0 >= now }
            .sorted())
        completion(Timeline(entries: refreshDates.map { entry(for: $0, timetable: timetable) }, policy: .after(tomorrow)))
    }

    private func loadTimetable() -> Timetable? {
        let defaults = UserDefaults(suiteName: KebiaoConfiguration.appGroupIdentifier)
        if let data = defaults?.data(forKey: KebiaoConfiguration.collectionStorageKey) {
            guard let collection = try? JSONDecoder().decode(TimetableCollection.self, from: data),
                  collection.version == 2 else { return nil }
            do {
                try collection.validate()
                return collection.activeTimetable
            } catch { return nil }
        }
        // Read the previous app's course-only storage until its first v2 save.
        let courses = defaults?.data(forKey: KebiaoConfiguration.storageKey)
            .flatMap { try? JSONDecoder().decode([Course].self, from: $0) } ?? []
        let semesterStart = defaults?.object(forKey: KebiaoConfiguration.semesterStartKey) as? Double
        return Timetable(name: "默认课表",
            semesterStartDate: semesterStart.map { Date(timeIntervalSince1970: $0) } ?? ScheduleEngine.semesterStart(for: .now),
            weekCount: 30, courses: courses)
    }

    private func entry(for date: Date, timetable: Timetable?) -> TodayEntry {
        TodayEntry(date: date, timetableName: timetable?.name ?? "今日课表",
            timeZoneIdentifier: timetable?.timeZoneIdentifier ?? TimeZone.current.identifier,
            occurrences: timetable.map { ScheduleEngine.occurrences(in: $0, on: date) } ?? [])
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
                Label(entry.timetableName, systemImage: "calendar")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(Weekday.from(calendarWeekday: entry.calendar.component(.weekday, from: entry.date)).fullName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if entry.occurrences.isEmpty {
                Spacer()
                Text("今天没有课程")
                    .font(.title3.weight(.semibold))
                Text("打开课表即可同步最新安排")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(visibleOccurrences) { occurrence in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(occurrence.course.color)
                            .frame(width: 4, height: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(occurrence.course.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(courseStatus(occurrence))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if family == .systemMedium {
                            Text(occurrence.location)
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

    private var visibleOccurrences: [CourseOccurrence] {
        let sorted = entry.occurrences.sorted { lhs, rhs in
            let lhsStart = lhs.startDate
            let rhsStart = rhs.startDate
            let lhsIsCurrent = entry.date >= lhsStart && entry.date < lhs.endDate
            let rhsIsCurrent = entry.date >= rhsStart && entry.date < rhs.endDate
            if lhsIsCurrent != rhsIsCurrent { return lhsIsCurrent }

            let lhsIsUpcoming = lhsStart >= entry.date
            let rhsIsUpcoming = rhsStart >= entry.date
            if lhsIsUpcoming != rhsIsUpcoming { return lhsIsUpcoming }
            if lhsStart == rhsStart { return lhs.id < rhs.id }
            return lhsIsUpcoming ? lhsStart < rhsStart : lhsStart > rhsStart
        }
        return Array(sorted.prefix(family == .systemSmall ? 2 : 4))
    }

    private func courseStatus(_ occurrence: CourseOccurrence) -> String {
        let course = occurrence.course
        if entry.date >= occurrence.startDate && entry.date < occurrence.endDate {
            return "进行中 · 第\(course.startSection)–\(course.endSection)节"
        }
        let formatter = DateFormatter()
        formatter.calendar = entry.calendar
        formatter.timeZone = entry.calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: occurrence.startDate)) · 第\(course.startSection)–\(course.endSection)节"
    }
}
