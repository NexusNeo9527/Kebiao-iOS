import SwiftUI

@main
struct KebiaoApp: App {
    @State private var store = TimetableStore()

    var body: some Scene {
        WindowGroup {
            AppView(store: store)
        }
    }
}
