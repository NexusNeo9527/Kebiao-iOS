#if targetEnvironment(simulator)
import SwiftUI

// Uses the extension's actual shared content. This host only exists on Simulator.
struct WidgetDiagnosticsHost: View {
    @State private var state: FixtureState = .ready
    private let date = ISO8601DateFormatter().date(from: "2026-10-10T04:00:00Z")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Menu {
                        ForEach(FixtureState.allCases) { value in
                            Button(value.title) { state = value }
                        }
                    } label: { Label("选择状态", systemImage: "list.bullet") }
                    .accessibilityIdentifier("widget-host-state-menu")
                    Text(state.title).accessibilityIdentifier("widget-host-state")
                    Text("小尺寸").font(.headline)
                    TodayWidgetContent(entry: entry, family: .small)
                        .frame(width: 170, height: 170)
                        .background(.white, in: RoundedRectangle(cornerRadius: 20))
                        .accessibilityIdentifier("widget-host-small")
                    Text("中尺寸").font(.headline)
                    TodayWidgetContent(entry: entry, family: .medium)
                        .frame(width: 338, height: 170)
                        .background(.white, in: RoundedRectangle(cornerRadius: 20))
                        .accessibilityIdentifier("widget-host-medium")
                    Text("共享内容测试宿主，主屏幕显示需要签名设备验收。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            }
            .background(Color(white: 0.96))
            .navigationTitle("小组件状态验收")
        }
        .preferredColorScheme(.light)
    }

    private var entry: TodayWidgetContentEntry {
        let snapshot: SharedTimetableSnapshot
        switch state {
        case .ready:
            let events = (0..<3).map { index in
                DatedCourseEvent(startDate: date.addingTimeInterval(Double(1800 + index * 7200)),
                    endDate: date.addingTimeInterval(Double(5400 + index * 7200)))
            }
            let course = Course(name: "软件工程", colorValue: 0x497CF3,
                timeSlots: [CourseTimeSlot(teacher: "张老师", location: "A301", datedEvents: events)])
            let table = Timetable(name: "秋季课表", timeZoneIdentifier: "Asia/Shanghai", courses: [course])
            snapshot = SharedTimetableSnapshot(state: .ready, collection: TimetableCollection(timetables: [table]), updatedAt: date.addingTimeInterval(-300))
        case .empty:
            let table = Timetable(name: "无课课表", timeZoneIdentifier: "Asia/Shanghai", courses: [])
            snapshot = SharedTimetableSnapshot(state: .empty, collection: TimetableCollection(timetables: [table]), updatedAt: date.addingTimeInterval(-300))
        case .notSynced: snapshot = SharedTimetableSnapshot(state: .notSynced)
        case .unavailable: snapshot = SharedTimetableSnapshot(state: .containerUnavailable)
        case .corrupt: snapshot = SharedTimetableSnapshot(state: .corrupt)
        case .unsupported: snapshot = SharedTimetableSnapshot(state: .unsupportedVersion(99))
        }
        return TodayWidgetContentEntry(date: date, snapshot: snapshot)
    }

    private enum FixtureState: String, CaseIterable, Identifiable {
        case ready, empty, notSynced, unavailable, corrupt, unsupported
        var id: String { rawValue }
        var title: String {
            switch self {
            case .ready: "正常有课"
            case .empty: "正常无课"
            case .notSynced: "尚未同步"
            case .unavailable: "共享容器不可用"
            case .corrupt: "数据损坏"
            case .unsupported: "版本不支持"
            }
        }
    }
}
#endif
