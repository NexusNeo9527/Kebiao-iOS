import Foundation
import Observation
import WidgetKit

@Observable
final class TimetableStore {
    private let defaults: UserDefaults
    var courses: [Course] = [] {
        didSet { save() }
    }

    init() {
        defaults = UserDefaults(suiteName: KebiaoConfiguration.appGroupIdentifier) ?? .standard
        guard let data = defaults.data(forKey: KebiaoConfiguration.storageKey),
              let saved = try? JSONDecoder().decode([Course].self, from: data) else {
            courses = Course.samples
            persist()
            return
        }
        courses = saved
    }

    func courses(on day: Weekday) -> [Course] {
        courses.filter { $0.weekdays.contains(day) }
            .sorted { $0.startSection < $1.startSection }
    }

    func save(_ course: Course) {
        var normalized = course
        normalized.normalize()
        if let index = courses.firstIndex(where: { $0.id == normalized.id }) {
            courses[index] = normalized
        } else {
            courses.append(normalized)
        }
    }

    func delete(_ course: Course) {
        courses.removeAll { $0.id == course.id }
    }

    private func save() {
        persist()
        let snapshot = courses
        Task {
            await ReminderScheduler.shared.reschedule(courses: snapshot)
            await LiveActivityCoordinator.refresh(courses: snapshot)
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(courses) else { return }
        defaults.set(data, forKey: KebiaoConfiguration.storageKey)
        WidgetCenter.shared.reloadTimelines(ofKind: KebiaoConfiguration.widgetKind)
    }
}
