import SwiftUI

struct AppView: View {
    let store: TimetableStore
    @State private var selectedTab: AppTab = {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-test-live-activity") { return .reminders }
        if arguments.contains("--ui-test-core") { return .schedule }
        if arguments.contains("--ui-test-overlap") { return .schedule }
        return arguments.contains("--ui-test-add-course") || arguments.contains(where: { $0.hasPrefix("--ui-test-import") }) ? .courses : .day
    }()
    @State private var scheduleDate = Date.now
    @State private var showingRecovery = false
    @AppStorage(ReminderPreferences.enabledKey) private var remindersEnabled = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DayScheduleView(store: store)
            }
            .tabItem { Label("日程", systemImage: "calendar.day.timeline.left") }
            .tag(AppTab.day)

            NavigationStack {
                ScheduleView(store: store, initialDate: scheduleDate)
                    .id(scheduleDate)
            }
            .tabItem { Label("课表", systemImage: "calendar") }
            .tag(AppTab.schedule)

            NavigationStack {
                CoursesView(store: store) { date in
                    scheduleDate = date
                    selectedTab = .schedule
                }
            }
            .tabItem { Label("课程", systemImage: "books.vertical") }
            .tag(AppTab.courses)
            NavigationStack {
                ReminderSettingsView(store: store)
            }
            .tabItem { Label("提醒", systemImage: "bell.badge") }
            .tag(AppTab.reminders)
        }
        .tint(KebiaoTheme.accent)
        .preferredColorScheme(.light)
        .safeAreaInset(edge: .top) {
            if store.isReadOnly {
                VStack(alignment: .leading, spacing: 8) {
                    Label("课表资料无法读取", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                    Text(store.errorMessage ?? "原始资料已保留，请从完整备份恢复后继续使用。")
                        .font(.caption).lineLimit(3)
                    Button("从备份恢复") { showingRecovery = true }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("read-only-recovery")
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                .foregroundStyle(.primary).background(Color.orange.opacity(0.15))
                .accessibilityIdentifier("read-only-data-warning")
            }
        }
        .sheet(isPresented: $showingRecovery) { BackupExportView(store: store) }
        .onOpenURL(perform: handleDeepLink)
        .task(id: store.activeTimetableID) {
            guard !Task.isCancelled else { return }
            let timetable = store.activeTimetable
            await ReminderScheduler.shared.reschedule(timetable: timetable)
            while !Task.isCancelled {
                if scenePhase == .active {
                    await LiveActivityCoordinator.refresh(timetable: store.activeTimetable)
                }
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                let timetable = store.activeTimetable
                await ReminderScheduler.shared.reschedule(timetable: timetable)
                guard store.activeTimetable == timetable else { return }
                await LiveActivityCoordinator.refresh(timetable: timetable)
            }
        }
        .onChange(of: remindersEnabled) { _, enabled in
            guard enabled else { return }
            Task { await ReminderScheduler.shared.reschedule(timetable: store.activeTimetable) }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == KebiaoConfiguration.scheduleURL.scheme else { return }
        selectedTab = .day
    }
}

private enum AppTab: Hashable {
    case day, schedule, courses, reminders
}
