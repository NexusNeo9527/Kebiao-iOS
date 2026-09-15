import SwiftUI

struct AppView: View {
    let store: TimetableStore
    @State private var selectedTab: AppTab = .schedule

    var body: some View {
        TabView(selection: $selectedTab) {
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
        }
        .tint(.indigo)
    }
}

private enum AppTab: Hashable {
    case schedule, courses
}
