import SwiftUI
import WidgetKit

struct WidgetSyncDiagnosticsView: View {
    let store: TimetableStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var snapshot = SharedTimetableSnapshot(state: .notSynced)
    @State private var actionMessage: String?

    var body: some View {
        Section {
            LabeledContent("共享数据", value: snapshot.state.title)
                .accessibilityIdentifier("widget-shared-state")
            if let table = snapshot.timetable {
                LabeledContent("共享课表", value: table.name)
                LabeledContent("课程数量", value: "\(table.courses.count) 门")
                if table.id != store.activeTimetableID {
                    Text("共享数据中的当前课表与 App 不一致，请保存课表后重新检查。")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            if let source = snapshot.source {
                LabeledContent("读取来源", value: source.rawValue)
            }
            Text(timestampText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("widget-sync-timestamp")
            if let detail = snapshot.detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(snapshot.state.isReadable ? Color.secondary : Color.orange)
            }
            Button("检查共享数据") {
                refresh()
                actionMessage = snapshot.state.isReadable ? "课表数据可读取。" : snapshot.state.title
            }
            .accessibilityIdentifier("widget-data-check")
            Button("请求刷新小组件") {
                WidgetCenter.shared.reloadTimelines(ofKind: KebiaoConfiguration.widgetKind)
                refresh()
                actionMessage = "已请求刷新小组件。"
            }
            .accessibilityIdentifier("widget-request-refresh")
            if let actionMessage {
                Text(actionMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("widget-refresh-message")
            }
        } header: {
            Text("小组件同步")
        } footer: {
            Text("这里只检查共享数据并请求刷新。主屏小组件是否显示最新内容，需要在具有 App Group 签名的设备上确认。")
        }
        .task { refresh() }
        .onChange(of: store.collection) { _, _ in refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }

    private var timestampText: String {
        guard let date = snapshot.updatedAt else { return "更新时间未知" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = snapshot.timetable?.calendar.timeZone ?? .current
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return "数据更新于 \(formatter.string(from: date))"
    }
    private func refresh() {
        snapshot = SharedTimetableReader.shared().read()
    }
}
