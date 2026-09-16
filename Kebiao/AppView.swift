import SwiftUI

struct AppView: View {
    let store: TimetableStore
    @State private var selectedTab: AppTab = ProcessInfo.processInfo.arguments.contains("--ui-test-add-course") ? .courses : .day
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
        .onOpenURL(perform: handleDeepLink)
        .task {
            await LiveActivityCoordinator.refresh(courses: store.courses)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
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
