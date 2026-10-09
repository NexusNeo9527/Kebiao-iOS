import SwiftUI

struct AppView: View {
    let store: TimetableStore
    @State private var selectedTab: AppTab = {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--ui-test-add-course") || arguments.contains("--ui-test-import") ? .courses : .day
    }()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DayScheduleView(store: store)
            }
            .tabItem { Label("日程", systemImage: "calendar.day.timeline.left") }
            .tag(AppTab.day)

            NavigationStack {
                ScheduleView(store: store)
            }
            .tabItem { Label("课表", systemImage: "calendar") }
            .tag(AppTab.schedule)

            NavigationStack {
                CoursesView(store: store)
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
        .onOpenURL(perform: handleDeepLink)
        .task {
            await ReminderScheduler.shared.reschedule(courses: store.courses)
            while !Task.isCancelled {
                if scenePhase == .active { await LiveActivityCoordinator.refresh(courses: store.courses) }
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await ReminderScheduler.shared.reschedule(courses: store.courses)
                await LiveActivityCoordinator.refresh(courses: store.courses)
            }
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
