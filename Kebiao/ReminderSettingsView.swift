import ActivityKit
import SwiftUI
import UIKit

struct ReminderSettingsView: View {
    let store: TimetableStore
    @AppStorage(ReminderPreferences.enabledKey) private var remindersEnabled = false
    @AppStorage(LiveActivityPreferences.enabledKey) private var liveActivitiesEnabled = true
    @State private var statusMessage: String?
    @State private var isRequesting = false
    @State private var isStartingActivity = false

    var body: some View {
        let activityStatus = LiveActivityCoordinator.status
        Form {
            Section("学期设置") {
                DatePicker("第一周所在日期", selection: Binding(
                    get: { store.semesterStartDate },
                    set: { store.semesterStartDate = $0 }
                ), displayedComponents: .date)
                Text("选择学校本学期第一周内的任意一天，课表、提醒和小组件会使用同一周次。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Toggle("启用上课通知", isOn: $remindersEnabled)
                    .disabled(isRequesting)
            } footer: {
                Text("按实际周次预排最近 60 次通知，每次打开 App 会补排。通知和下方实时活动可以分别开启。")
            }

            Section("灵动岛与锁屏") {
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
        .task {
            await LiveActivityCoordinator.refresh(courses: store.courses)
        }
        .onChange(of: remindersEnabled) { _, enabled in
            updateReminderState(enabled)
        }
        .onChange(of: liveActivitiesEnabled) { _, _ in
            Task {
                await LiveActivityCoordinator.endAll()
                await LiveActivityCoordinator.refresh(courses: store.courses)
            }
        }
    }

    private func updateReminderState(_ enabled: Bool) {
        isRequesting = true
        Task {
            if enabled {
                let granted = await ReminderScheduler.shared.requestAuthorizationAndReschedule(courses: store.courses)
                remindersEnabled = granted
                statusMessage = granted ? "上课通知已开启。" : "通知权限未开启，请到系统设置中允许通知。"
            } else {
                await ReminderScheduler.shared.disable()
                statusMessage = "上课通知已关闭。"
            }
            isRequesting = false
        }
    }

    private func refreshLiveActivity() {
        isStartingActivity = true
        Task {
            await LiveActivityCoordinator.endAll()
            await LiveActivityCoordinator.refresh(courses: store.courses)
            isStartingActivity = false
        }
    }

    private func previewLiveActivity() {
        let course = ScheduleEngine.currentOrUpcomingOccurrence(in: store.courses, at: .now)?.course
            ?? store.courses.first
        guard let course else { return }
        isStartingActivity = true
        Task {
            do {
                try await LiveActivityCoordinator.preview(course: course)
                statusMessage = nil
            } catch {
                statusMessage = error.localizedDescription
            }
            isStartingActivity = false
        }
    }
}
