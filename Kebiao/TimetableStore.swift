import Foundation
import Observation
import WidgetKit

@Observable
final class TimetableStore {
    enum ImportMode {
        case merge
        case replace
    }

    private let defaults: UserDefaults
    var courses: [Course] = [] {
        didSet { save() }
    }

    init() {
        defaults = UserDefaults(suiteName: KebiaoConfiguration.appGroupIdentifier) ?? .standard
        let existingData = defaults.data(forKey: KebiaoConfiguration.storageKey)
            ?? UserDefaults.standard.data(forKey: KebiaoConfiguration.storageKey)
        guard let data = existingData,
              let saved = try? JSONDecoder().decode([Course].self, from: data) else {
            courses = Course.samples
            persist()
            return
        }
        courses = saved
        if defaults.data(forKey: KebiaoConfiguration.storageKey) == nil {
            persist()
        }
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

    func duplicate(_ course: Course) {
        var copy = course
        copy.id = UUID()
        copy.name += " 副本"
        save(copy)
    }

    func importCourses(_ imported: [Course], mode: ImportMode) {
        let normalized = imported.map { course -> Course in
            var value = course
            value.normalize()
            return value
        }

        switch mode {
        case .replace:
            courses = normalized
        case .merge:
            var result = courses
            for course in normalized {
                let signature = CourseSignature(course)
                if let index = result.firstIndex(where: { CourseSignature($0) == signature }) {
                    var updated = course
                    updated.id = result[index].id
                    result[index] = updated
                } else {
                    result.append(course)
                }
            }
            courses = result
        }
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
        WidgetCenter.shared.reloadAllTimelines()
    }
}

private struct CourseSignature: Equatable {
    let name: String
    let teacher: String
    let location: String
    let startSection: Int
    let weekdays: Set<Weekday>

    init(_ course: Course) {
        name = course.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        teacher = course.teacher.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        location = course.location.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        startSection = course.startSection
        weekdays = course.weekdays
    }
}
