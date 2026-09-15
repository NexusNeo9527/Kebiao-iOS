import ActivityKit
import SwiftUI

struct ReminderSettingsView: View {
    let store: TimetableStore
    @AppStorage(ReminderPreferences.enabledKey) private var remindersEnabled = false
    @State private var statusMessage: String?
    @State private var isRequesting = false

    var body: some View {
        Form {
            Section {
                Toggle("启用上课提醒", isOn: $remindersEnabled)
                    .disabled(isRequesting)
            } footer: {
                Text("开启后会按每门课程设置的提前时间发送本地通知。")
            }

            Section("灵动岛与锁屏") {
                LabeledContent("实时活动") {
                    Text(ActivityAuthorizationInfo().areActivitiesEnabled ? "系统已允许" : "系统未允许")
                        .foregroundStyle(ActivityAuthorizationInfo().areActivitiesEnabled ? .green : .secondary)
                }

                Button("预览下一门课的灵动岛") {
                    previewLiveActivity()
                }
                .disabled(store.courses.isEmpty || !remindersEnabled)
            }

            Section {
                Text("支持灵动岛的 iPhone 会在课前显示倒计时；其他设备显示锁屏实时活动。离线提醒由系统本地通知保证。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("上课提醒")
        .onChange(of: remindersEnabled) { _, enabled in
            updateReminderState(enabled)
        }
    }

    private func updateReminderState(_ enabled: Bool) {
        isRequesting = true
        Task {
            if enabled {
                let granted = await ReminderScheduler.shared.requestAuthorizationAndReschedule(courses: store.courses)
                await MainActor.run {
                    remindersEnabled = granted
                    statusMessage = granted ? "提醒已开启。" : "通知权限未开启，请到系统设置中允许通知。"
                    isRequesting = false
                }
            } else {
                await ReminderScheduler.shared.disable()
                await LiveActivityCoordinator.endAll()
                await MainActor.run {
                    statusMessage = "提醒已关闭。"
                    isRequesting = false
                }
            }
        }
    }

    private func previewLiveActivity() {
        guard let course = store.courses.first else { return }
        Task {
            do {
                try await LiveActivityCoordinator.preview(course: course)
                await MainActor.run {
                    statusMessage = "已创建 5 分钟倒计时预览，请查看灵动岛或锁屏。"
                }
            } catch {
                await MainActor.run {
                    statusMessage = error.localizedDescription
                }
            }
        }
    }
}
