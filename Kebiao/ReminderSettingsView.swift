import ActivityKit
import SwiftUI
import UIKit

struct ReminderSettingsView: View {
    let store: TimetableStore
    let scheduler: ReminderScheduler
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(ReminderPreferences.enabledKey) private var remindersEnabled = false
    @AppStorage(LiveActivityPreferences.enabledKey) private var liveActivitiesEnabled = true
    @State private var statusMessage: String?
    @State private var isRequesting = false
    @State private var isStartingActivity = false
    @State private var diagnostics: ReminderDiagnostics?
    @State private var diagnosticsMessage: String?
    @State private var diagnosticQuery = 0
    @State private var operationRevision = 0
    @State private var requestRevision = 0
    @State private var rescheduleRevision = 0
    @State private var isRescheduling = false

    init(store: TimetableStore, scheduler: ReminderScheduler = .shared) {
        self.store = store
        self.scheduler = scheduler
    }

    var body: some View {
        let activityStatus = LiveActivityCoordinator.status
        Form {
            Section("学期设置") {
                NavigationLink {
                    TimetableSettingsView(store: store)
                } label: {
                    LabeledContent("当前课表", value: store.activeTimetable.name)
                }
                Text("设置当前课表的学期、周数、时区与作息时间。日程、提醒和小组件共用这些安排。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Toggle("启用上课通知", isOn: $remindersEnabled)
                    .disabled(isRequesting)
            } footer: {
                Text("按实际周次预排最近 60 次通知，每次打开 App 会补排。通知和下方实时活动可以分别开启。")
            }

            reminderDiagnosticsSection
            WidgetSyncDiagnosticsView(store: store)

            Section {
                Toggle("自动显示课程实时活动", isOn: $liveActivitiesEnabled)
                    .disabled(isStartingActivity)
                    .accessibilityIdentifier("live-activity-toggle")

                LabeledContent("系统权限") {
                    Text(ActivityAuthorizationInfo().areActivitiesEnabled ? "已允许" : "未允许")
                        .foregroundStyle(ActivityAuthorizationInfo().areActivitiesEnabled ? .green : .secondary)
                }

                Text(activityStatus.message)
                    .font(.footnote)
                    .foregroundStyle(activityStatus.phase == .failed ? Color.red : Color.secondary)
                    .accessibilityIdentifier("live-activity-status")

                Button("立即显示当前或下一门课") {
                    refreshLiveActivity()
                }
                .disabled(!liveActivitiesEnabled || store.courses.isEmpty || isStartingActivity)
                .accessibilityIdentifier("live-activity-refresh")

                Button("预览灵动岛效果（5 分钟倒计时）") {
                    previewLiveActivity()
                }
                .disabled(store.courses.isEmpty || isStartingActivity)
                .accessibilityIdentifier("live-activity-preview")

                if !ActivityAuthorizationInfo().areActivitiesEnabled {
                    Link("打开系统设置", destination: URL(string: UIApplication.openSettingsURLString)!)
                }

                if let activityID = activityStatus.activityID {
                    DisclosureGroup("活动诊断") {
                        LabeledContent("系统状态", value: activityStatus.activityState ?? "未知")
                        Text(activityID)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .accessibilityIdentifier("live-activity-id")
                        Text("系统已激活但主屏仍没有内容时，请确认安装工具同时保留并签名了课表小组件扩展。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("灵动岛与锁屏")
            } footer: {
                Text("打开 App 时，会显示当天 6 小时内的当前或下一门课；通知关闭也可使用。返回主屏查看计时，长按灵动岛查看教室。无灵动岛的设备显示锁屏实时活动。没有临近课程时可点预览。")
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("上课提醒")
        .task(id: store.activeTimetable) {
            diagnostics = nil
            statusMessage = nil
            await refreshDiagnostics()
            await LiveActivityCoordinator.refresh(timetable: store.activeTimetable)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshDiagnostics() } }
        }
        .onChange(of: remindersEnabled) { _, enabled in
            updateReminderState(enabled)
        }
        .onChange(of: liveActivitiesEnabled) { _, _ in
            Task {
                await LiveActivityCoordinator.endAll()
                await LiveActivityCoordinator.refresh(timetable: store.activeTimetable)
            }
        }
    }

    private var reminderDiagnosticsSection: some View {
        Section {
            if let diagnostics, diagnostics.timetableID == store.activeTimetableID {
                LabeledContent("App 通知开关", value: diagnostics.appEnabled ? "已开启" : "已关闭")
                LabeledContent("通知系统权限", value: diagnostics.settings.authorization.description)
                    .accessibilityIdentifier("reminder-permission")
                LabeledContent("横幅", value: diagnostics.settings.alerts.description)
                LabeledContent("声音", value: diagnostics.settings.sound.description)
                LabeledContent("当前课表已排程", value: "\(diagnostics.scheduledCount) 条")
                    .accessibilityIdentifier("reminder-pending-count")
                LabeledContent("下一次提醒", value: nextReminderDescription(diagnostics.nextReminderDate))
                    .accessibilityIdentifier("reminder-next-date")
                if diagnostics.otherTimetableCount > 0 {
                    Text("发现 \(diagnostics.otherTimetableCount) 条其他课表或旧格式提醒，重新排程可清理。")
                        .font(.footnote).foregroundStyle(.orange)
                        .accessibilityIdentifier("reminder-other-count")
                }
                if let failure = diagnostics.recentFailure {
                    Text("最近排程：\(failure.attemptedCount - failure.failedCount) 条成功，\(failure.failedCount) 条失败。\(failure.message)")
                        .font(.footnote).foregroundStyle(.red)
                        .accessibilityIdentifier("reminder-last-failure")
                } else {
                    Text("最近排程未记录失败。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                Text(diagnosticsMessage ?? "正在读取系统提醒状态…").foregroundStyle(.secondary)
            }
            Button("检查提醒状态") { Task { await refreshDiagnostics() } }
                .accessibilityIdentifier("reminder-check")
            Button("重新排程") { rescheduleReminders() }
                .disabled(!remindersEnabled || isRequesting || isRescheduling)
                .accessibilityIdentifier("reminder-reschedule")
            Link("打开通知系统设置", destination: URL(string: UIApplication.openSettingsURLString)!)
                .accessibilityIdentifier("reminder-open-settings")
        } header: {
            Text("通知诊断")
        } footer: {
            Text("数量和下一次提醒来自系统待投递队列。系统权限、横幅、声音分别控制通知效果；已排程并不代表已送达。重新排程不会申请权限。")
        }
        .accessibilityIdentifier("reminder-diagnostics")
    }

    private func nextReminderDescription(_ date: Date?) -> String {
        guard let date else { return "暂无待投递提醒" }
        let formatter = DateFormatter()
        formatter.calendar = store.activeTimetable.calendar
        formatter.timeZone = store.activeTimetable.calendar.timeZone
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: date)
    }

    @MainActor
    private func refreshDiagnostics() async {
        diagnosticQuery += 1
        let query = diagnosticQuery
        let timetable = store.activeTimetable
        diagnosticsMessage = nil
        for _ in 0..<3 {
            let value = await scheduler.diagnostics(timetable: timetable)
            guard query == diagnosticQuery, timetable == store.activeTimetable, !Task.isCancelled else { return }
            if let value {
                diagnostics = value
                return
            }
            await Task.yield()
        }
        diagnosticsMessage = store.isReadOnly
            ? "课表数据暂时无法读取，无法检查对应提醒。请先恢复有效课表。"
            : "课表或排程正在更新，暂时无法完成检查。请稍后检查提醒状态。"
    }

    private func rescheduleReminders() {
        let timetable = store.activeTimetable
        operationRevision += 1
        let revision = operationRevision
        rescheduleRevision += 1
        let busyRevision = rescheduleRevision
        isRescheduling = true
        Task {
            defer { if busyRevision == rescheduleRevision { isRescheduling = false } }
            await scheduler.reschedule(timetable: timetable)
            guard revision == operationRevision else { return }
            guard timetable == store.activeTimetable else { return }
            await refreshDiagnostics()
            guard revision == operationRevision, timetable == store.activeTimetable else { return }
            statusMessage = "已检查系统权限并重排允许的通知；请查看通知诊断中的实际队列。"
        }
    }

    private func updateReminderState(_ enabled: Bool) {
        operationRevision += 1
        let revision = operationRevision
        requestRevision += 1
        let busyRevision = requestRevision
        let timetable = store.activeTimetable
        isRequesting = true
        Task {
            defer { if busyRevision == requestRevision { isRequesting = false } }
            if enabled {
                let granted = await scheduler.requestAuthorizationAndReschedule(timetable: timetable)
                guard revision == operationRevision else { return }
                guard timetable == store.activeTimetable else { return }
                remindersEnabled = granted
                statusMessage = granted ? "通知权限已允许，请查看实际排程结果。" : "通知权限未开启，请到系统设置中允许通知。"
            } else {
                await scheduler.disable()
                guard revision == operationRevision else { return }
                statusMessage = "上课通知已关闭。"
            }
            await refreshDiagnostics()
        }
    }

    private func refreshLiveActivity() {
        isStartingActivity = true
        Task {
            await LiveActivityCoordinator.endAll()
            await LiveActivityCoordinator.refresh(timetable: store.activeTimetable)
            isStartingActivity = false
        }
    }

    private func previewLiveActivity() {
        let timetable = store.activeTimetable
        guard !timetable.courses.isEmpty else { return }
        isStartingActivity = true
        Task {
            do {
                try await LiveActivityCoordinator.preview(timetable: timetable)
                statusMessage = nil
            } catch {
                statusMessage = error.localizedDescription
            }
            isStartingActivity = false
        }
    }
}
