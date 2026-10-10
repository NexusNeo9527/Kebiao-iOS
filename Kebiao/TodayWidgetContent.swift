import SwiftUI

enum TodayWidgetContentFamily: Equatable { case small, medium }

struct TodayWidgetContentEntry {
    let date: Date
    let snapshot: SharedTimetableSnapshot
    let occurrences: [CourseOccurrence]

    init(date: Date, snapshot: SharedTimetableSnapshot) {
        self.date = date; self.snapshot = snapshot
        occurrences = snapshot.timetable.map { ScheduleEngine.occurrencesOverlappingDay(in: $0, on: date) } ?? []
    }
    var timetableName: String { snapshot.timetable?.name ?? "今日课表" }
    var calendar: Calendar { snapshot.timetable?.calendar ?? .current }
}

/// Used by the real extension and the simulator screenshot host, with identical content.
struct TodayWidgetContent: View {
    let entry: TodayWidgetContentEntry
    let family: TodayWidgetContentFamily

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Label(entry.timetableName, systemImage: "calendar")
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(Weekday.from(calendarWeekday: entry.calendar.component(.weekday, from: entry.date)).fullName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !entry.snapshot.state.isReadable {
                failureContent
            } else if entry.occurrences.isEmpty {
                Spacer(minLength: 0)
                Text("今天没有课程")
                    .font(.title3.weight(.semibold))
                Text("课表数据可读取")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ForEach(visibleOccurrences) { occurrence in
                    courseRow(occurrence)
                }
                Spacer(minLength: 0)
            }
            if entry.snapshot.state.isReadable {
                Text(timestampText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(12)
        .accessibilityElement(children: .contain)
    }

    private var failureContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            Spacer(minLength: 0)
            Image(systemName: failureIcon)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(failureTitle)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(failureHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func courseRow(_ occurrence: CourseOccurrence) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 3)
                .fill(occurrence.course.color)
                .frame(width: 4, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(occurrence.course.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(courseStatus(occurrence))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if family == .medium, !occurrence.location.isEmpty {
                Text(occurrence.location)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var visibleOccurrences: [CourseOccurrence] {
        let sorted = entry.occurrences.sorted { lhs, rhs in
            let lhsCurrent = entry.date >= lhs.startDate && entry.date < lhs.endDate
            let rhsCurrent = entry.date >= rhs.startDate && entry.date < rhs.endDate
            if lhsCurrent != rhsCurrent { return lhsCurrent }
            let lhsUpcoming = lhs.startDate >= entry.date
            let rhsUpcoming = rhs.startDate >= entry.date
            if lhsUpcoming != rhsUpcoming { return lhsUpcoming }
            if lhs.startDate == rhs.startDate { return lhs.id < rhs.id }
            return lhsUpcoming ? lhs.startDate < rhs.startDate : lhs.startDate > rhs.startDate
        }
        return Array(sorted.prefix(family == .small ? 2 : 3))
    }

    private var timestampText: String {
        guard let updated = entry.snapshot.updatedAt else { return "更新时间未知" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = entry.calendar.timeZone
        formatter.dateFormat = "MM/dd HH:mm"
        return "数据更新于 \(formatter.string(from: updated))"
    }
    private var failureIcon: String {
        switch entry.snapshot.state {
        case .notSynced: return "arrow.triangle.2.circlepath"
        case .containerUnavailable: return "externaldrive.badge.exclamationmark"
        default: return "exclamationmark.triangle"
        }
    }
    private var failureTitle: String {
        switch entry.snapshot.state {
        case .notSynced: return "尚未同步课表"
        case .containerUnavailable: return "共享同步不可用"
        case .unsupportedVersion: return "数据版本暂不支持"
        default: return "课表数据无法读取"
        }
    }
    private var failureHint: String {
        switch entry.snapshot.state {
        case .notSynced: return "请打开 App 保存课表"
        case .containerUnavailable: return "请检查 App Group 共享配置"
        case .unsupportedVersion: return "请更新 App 与小组件"
        default: return "请打开 App 检查或恢复备份"
        }
    }
    private func courseStatus(_ occurrence: CourseOccurrence) -> String {
        if entry.date >= occurrence.startDate && entry.date < occurrence.endDate {
            return "进行中 · 第\(occurrence.course.startSection)–\(occurrence.course.endSection)节"
        }
        let formatter = DateFormatter()
        formatter.calendar = entry.calendar
        formatter.timeZone = entry.calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: occurrence.startDate)) · 第\(occurrence.course.startSection)–\(occurrence.course.endSection)节"
    }
}
