import Foundation
import Observation
import WidgetKit

@Observable
final class TimetableStore {
    static let appGroup = "group.com.example.kebiao"
    private let storageKey = "kebiao.courses.v1"
    private let defaults: UserDefaults
    var courses: [Course] = [] {
        didSet { save() }
    }

    init() {
        defaults = UserDefaults(suiteName: Self.appGroup) ?? .standard
        guard let data = defaults.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([Course].self, from: data) else {
            courses = Course.samples
            return
        }
        courses = saved
    }

    func courses(on day: Weekday) -> [Course] {
        courses.filter { $0.weekdays.contains(day) }
            .sorted { $0.startSection < $1.startSection }
    }

    func save(_ course: Course) {
        if let index = courses.firstIndex(where: { $0.id == course.id }) {
            courses[index] = course
        } else {
            courses.append(course)
        }
    }

    func delete(_ course: Course) {
        courses.removeAll { $0.id == course.id }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(courses) else { return }
        defaults.set(data, forKey: storageKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "KebiaoTodayWidget")
    }
}
