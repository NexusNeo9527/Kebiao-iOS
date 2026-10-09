import Foundation
import Observation
import WidgetKit

@Observable
@MainActor
final class TimetableStore {
    enum ImportMode { case merge, replace }
    private let defaults: UserDefaults
    private let performsSystemUpdates: Bool
    private var revision = 0
    private var retainedSourceData: Data?
    private(set) var collection: TimetableCollection
    private(set) var isReadOnly = false
    var errorMessage: String?

    var timetables: [Timetable] { collection.timetables }
    var activeTimetableID: UUID { collection.activeTimetableID }
    var activeTimetable: Timetable { timetables.first { $0.id == activeTimetableID } ?? timetables[0] }
    var courses: [Course] {
        get { activeTimetable.courses }
        set {
            var updated = collection
            guard let index = updated.timetables.firstIndex(where: { $0.id == activeTimetableID }) else { return }
            updated.timetables[index].courses = newValue
            expandWeeks(in: &updated.timetables[index])
            _ = commit(updated)
        }
    }
    var semesterStartDate: Date {
        get { activeTimetable.semesterStartDate }
        set { var table = activeTimetable; table.semesterStartDate = newValue; _ = updateTimetable(table) }
    }

    init(defaults suppliedDefaults: UserDefaults? = nil, performsSystemUpdates: Bool = true) {
        defaults = suppliedDefaults ?? UserDefaults(suiteName: KebiaoConfiguration.appGroupIdentifier) ?? .standard
        self.performsSystemUpdates = performsSystemUpdates
        let first = Timetable(name: "我的课表", semesterStartDate: ScheduleEngine.defaultSemesterStart(for: .now))
        collection = TimetableCollection(timetables: [first], activeTimetableID: first.id)
        #if targetEnvironment(simulator)
        if suppliedDefaults == nil, ProcessInfo.processInfo.arguments.contains("--ui-test-core") {
            let firstSlot = CourseTimeSlot(teacher: "王老师", location: "A301", weekdays: [.monday, .friday], activeWeeks: [1, 3, 5])
            let secondSlot = CourseTimeSlot(teacher: "李老师", location: "B202", startSection: 5, weekdays: [.tuesday], activeWeeks: [2, 4, 6])
            let firstTable = Timetable(name: "秋季课表", courses: [Course(name: "多时段测试课程", colorValue: 0x5477D9, timeSlots: [firstSlot, secondSlot])])
            let secondTable = Timetable(name: "备用课表")
            collection = TimetableCollection(timetables: [firstTable, secondTable], activeTimetableID: firstTable.id)
            return
        }
        if suppliedDefaults == nil, let fixture = simulatorFixture() {
            collection = TimetableCollection(timetables: [fixture], activeTimetableID: fixture.id)
            return
        }
        #endif
        if let data = defaults.data(forKey: KebiaoConfiguration.collectionStorageKey) {
            retainedSourceData = data
            do {
                let saved = try JSONDecoder().decode(TimetableCollection.self, from: data)
                try saved.validate()
                collection = saved
            } catch { suspendEditing("课表数据无法读取", error: error) }
            return
        }
        let legacyDefaults = suppliedDefaults == nil ? UserDefaults.standard : defaults
        let legacyData = defaults.data(forKey: KebiaoConfiguration.storageKey) ?? legacyDefaults.data(forKey: KebiaoConfiguration.storageKey)
        if let legacyData {
            retainedSourceData = legacyData
            do {
                var migrated = first
                migrated.courses = try JSONDecoder().decode([Course].self, from: legacyData)
                if let timestamp = (defaults.object(forKey: KebiaoConfiguration.semesterStartKey) ?? legacyDefaults.object(forKey: KebiaoConfiguration.semesterStartKey)) as? Double {
                    migrated.semesterStartDate = Date(timeIntervalSince1970: timestamp)
                }
                expandWeeks(in: &migrated)
                let replacement = TimetableCollection(timetables: [migrated], activeTimetableID: migrated.id)
                try replacement.validate()
                defaults.set(try JSONEncoder().encode(replacement), forKey: KebiaoConfiguration.collectionStorageKey)
                collection = replacement
                // Both legacy keys remain intact; writing v2 is the final migration step.
            } catch { suspendEditing("旧课表迁移失败", error: error) }
        } else {
            var seeded = first
            seeded.courses = Course.samples
            collection = TimetableCollection(timetables: [seeded], activeTimetableID: seeded.id)
            do { defaults.set(try JSONEncoder().encode(collection), forKey: KebiaoConfiguration.collectionStorageKey) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func timetable(id: UUID) -> Timetable? { timetables.first { $0.id == id } }
    @discardableResult func selectTimetable(id: UUID) -> Bool {
        guard timetable(id: id) != nil else { return fail("这张课表已被删除。") }
        var updated = collection; updated.activeTimetableID = id
        return commit(updated)
    }
    @discardableResult func chooseTimetable(id: UUID) -> Bool { selectTimetable(id: id) }
    @discardableResult func addTimetable(name: String) -> Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return fail("请输入课表名称。") }
        let table = Timetable(name: clean, semesterStartDate: ScheduleEngine.defaultSemesterStart(for: .now))
        var updated = collection; updated.timetables.append(table); updated.activeTimetableID = table.id
        return commit(updated)
    }
    @discardableResult func updateTimetable(_ draft: Timetable) -> Bool {
        var updated = collection
        guard let index = updated.timetables.firstIndex(where: { $0.id == draft.id }) else { return fail("这张课表已被删除。") }
        var table = updated.timetables[index]
        table.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        table.semesterStartDate = draft.semesterStartDate; table.weekCount = draft.weekCount
        table.timeZoneIdentifier = draft.timeZoneIdentifier; table.sectionPeriods = draft.sectionPeriods
        let last = maximumWeek(in: table.courses)
        guard table.weekCount >= last else { return fail("已有课程使用第 \(last) 周，请先调整课程周次。") }
        updated.timetables[index] = table
        return commit(updated)
    }
    @discardableResult func duplicateTimetable(id: UUID) -> Bool {
        guard let original = timetable(id: id) else { return fail("这张课表已被删除。") }
        var copy = reidentified(original); copy.name += " 副本"
        var updated = collection; updated.timetables.append(copy); updated.activeTimetableID = copy.id
        return commit(updated)
    }
    @discardableResult func deleteTimetable(id: UUID) -> Bool {
        guard timetables.count > 1 else { return fail("至少需要保留一张课表。") }
        var updated = collection; updated.timetables.removeAll { $0.id == id }
        if updated.activeTimetableID == id { updated.activeTimetableID = updated.timetables[0].id }
        return commit(updated)
    }

    @discardableResult func save(_ course: Course, into tableID: UUID? = nil) -> Bool {
        var updated = collection
        guard let index = updated.timetables.firstIndex(where: { $0.id == (tableID ?? activeTimetableID) }) else { return fail("目标课表已被删除。") }
        var value = course; value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let courseIndex = updated.timetables[index].courses.firstIndex(where: { $0.id == value.id }) {
            updated.timetables[index].courses[courseIndex] = value
        } else { updated.timetables[index].courses.append(value) }
        expandWeeks(in: &updated.timetables[index])
        return commit(updated)
    }
    @discardableResult func delete(_ course: Course, from tableID: UUID? = nil) -> Bool {
        var updated = collection
        guard let index = updated.timetables.firstIndex(where: { $0.id == (tableID ?? activeTimetableID) }) else { return fail("目标课表已被删除。") }
        updated.timetables[index].courses.removeAll { $0.id == course.id }
        return commit(updated)
    }
    @discardableResult func duplicate(_ course: Course, into tableID: UUID? = nil) -> Bool {
        var copy = reidentified(course); copy.name += " 副本"
        return save(copy, into: tableID)
    }
    @discardableResult func importCourses(_ imported: [Course], mode: ImportMode, into tableID: UUID? = nil) -> Bool {
        var updated = collection
        guard let index = updated.timetables.firstIndex(where: { $0.id == (tableID ?? activeTimetableID) }) else { return fail("目标课表已被删除。") }
        switch mode {
        case .replace: updated.timetables[index].courses = imported.map { reidentified($0) }
        case .merge:
            for value in imported {
                // Compare the complete rule, never its name alone or a mutable resolved bell time.
                if !value.exceptions.isEmpty || !updated.timetables[index].courses.contains(where: { CourseSignature($0) == CourseSignature(value) }) {
                    updated.timetables[index].courses.append(reidentified(value))
                }
            }
        }
        expandWeeks(in: &updated.timetables[index])
        return commit(updated)
    }
    func courses(on day: Weekday) -> [Course] {
        let date = day.date(inWeekContaining: .now, calendar: activeTimetable.calendar)
        return ScheduleEngine.occurrences(in: activeTimetable, on: date).map(\.course)
    }
    @discardableResult func setException(_ exception: CourseException, for occurrence: CourseOccurrence) -> Bool {
        guard var original = timetable(id: occurrence.timetableID)?.courses.first(where: { $0.id == occurrence.course.id }) else { return fail("课程已被删除。") }
        original.exceptions.removeAll { $0.slotID == occurrence.slotID && $0.source == occurrence.source }
        original.exceptions.append(exception)
        return save(original, into: occurrence.timetableID)
    }
    @discardableResult func restoreOccurrence(_ occurrence: CourseOccurrence) -> Bool {
        guard var original = timetable(id: occurrence.timetableID)?.courses.first(where: { $0.id == occurrence.course.id }) else { return fail("课程已被删除。") }
        original.exceptions.removeAll { $0.slotID == occurrence.slotID && $0.source == occurrence.source }
        return save(original, into: occurrence.timetableID)
    }

    var originalData: Data? {
        defaults.data(forKey: KebiaoConfiguration.collectionStorageKey) ?? defaults.data(forKey: KebiaoConfiguration.storageKey) ?? retainedSourceData
    }
    var hasRecoverySnapshot: Bool { defaults.data(forKey: KebiaoConfiguration.recoverySnapshotKey) != nil }
    @discardableResult func restoreBackup(_ backup: TimetableCollection, replaceAll: Bool) -> Bool {
        do {
            try backup.validate()
            var replacement = backup
            if !replaceAll {
                guard !isReadOnly else { return fail("原始数据无法读取时，请选择完整恢复；原始资料会保留为恢复前快照。") }
                replacement = collection
                let copies = backup.timetables.map { reidentified($0) }
                replacement.timetables += copies
                if let index = backup.timetables.firstIndex(where: { $0.id == backup.activeTimetableID }) { replacement.activeTimetableID = copies[index].id }
            }
            try replacement.validate()
            let encoded = try JSONEncoder().encode(replacement)
            if replaceAll, let originalData { defaults.set(originalData, forKey: KebiaoConfiguration.recoverySnapshotKey) }
            let wasReadOnly = isReadOnly; isReadOnly = false
            if commit(replacement, encoded: encoded) { return true }
            isReadOnly = wasReadOnly
            return false
        } catch { return fail(error.localizedDescription) }
    }
    @discardableResult func restorePreviousSnapshot() -> Bool {
        guard let data = defaults.data(forKey: KebiaoConfiguration.recoverySnapshotKey) else { return fail("没有可恢复的快照。") }
        do { return restoreBackup(try JSONDecoder().decode(TimetableCollection.self, from: data), replaceAll: true) }
        catch { return fail("恢复前快照无法解码，原始文件仍已保留。\(error.localizedDescription)") }
    }

    private func commit(_ replacement: TimetableCollection, encoded: Data? = nil) -> Bool {
        guard !isReadOnly else { return fail("原始课表读取失败，编辑已暂停；请先从备份恢复，原始资料不会被覆盖。") }
        do {
            try replacement.validate()
            let data = try encoded ?? JSONEncoder().encode(replacement)
            defaults.set(data, forKey: KebiaoConfiguration.collectionStorageKey)
            collection = replacement; errorMessage = nil; revision += 1
            let currentRevision = revision
            let snapshot = activeTimetable
            if performsSystemUpdates {
                WidgetCenter.shared.reloadAllTimelines()
                Task {
                    guard currentRevision == revision else { return }
                    await ReminderScheduler.shared.reschedule(timetable: snapshot)
                    guard currentRevision == revision else { return }
                    await LiveActivityCoordinator.refresh(timetable: snapshot)
                }
            }
            return true
        } catch { return fail(error.localizedDescription) }
    }
    private func suspendEditing(_ title: String, error: Error) {
        isReadOnly = true
        errorMessage = "\(title)，原始资料已保留。请导出原始数据或从备份恢复。\(error.localizedDescription)"
    }
    private func fail(_ message: String) -> Bool { errorMessage = message; return false }
    private func maximumWeek(in values: [Course]) -> Int {
        values.flatMap(\.timeSlots).filter { $0.datedEvents == nil }.map { $0.activeWeeks.map { $0.max() ?? 0 } ?? $0.resolvedEndWeek }.max() ?? 1
    }
    private func expandWeeks(in table: inout Timetable) { table.weekCount = max(table.weekCount, maximumWeek(in: table.courses)) }
    private func reidentified(_ table: Timetable) -> Timetable {
        var copy = table; copy.id = UUID(); copy.courses = table.courses.map { reidentified($0) }; return copy
    }
    private func reidentified(_ course: Course) -> Course {
        var copy = course; copy.id = UUID()
        var slotIDs: [UUID: UUID] = [:]
        var eventIDs: [UUID: UUID] = [:]
        copy.timeSlots = course.timeSlots.map { slot in
            var changed = slot; changed.id = UUID(); slotIDs[slot.id] = changed.id
            changed.datedEvents = slot.datedEvents?.map { event in
                var changedEvent = event; changedEvent.id = UUID(); eventIDs[event.id] = changedEvent.id
                return changedEvent
            }
            return changed
        }
        copy.exceptions = course.exceptions.compactMap { exception in
            guard let slotID = slotIDs[exception.slotID] else { return nil }
            var changed = exception; changed.id = UUID(); changed.slotID = slotID
            if case .dated(let id) = exception.source {
                guard let eventID = eventIDs[id] else { return nil }
                changed.source = .dated(eventID)
            }
            return changed
        }
        return copy
    }

    #if targetEnvironment(simulator)
    private func simulatorFixture() -> Timetable? {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--ui-test-live-activity") {
            UserDefaults.standard.set(true, forKey: LiveActivityPreferences.enabledKey)
            UserDefaults.standard.set(false, forKey: ReminderPreferences.enabledKey)
            let start = Date.now.addingTimeInterval(5 * 60)
            return Timetable(name: "测试课表", courses: [Course(name: "灵动岛测试课程", teacher: "测试教师", location: "A301",
                startSection: 5, sectionCount: 2, weekdays: [.friday], colorValue: 0x5477D9,
                startTimeMinutes: 840, reminderMinutesBefore: nil, scheduledDates: [start], durationMinutes: 50)])
        }
        if args.contains("--ui-test-overlap") {
            return Timetable(name: "测试课表", weekCount: 30, courses: (0..<4).map { index in
                Course(name: ["轻量级应用开发", "管理学", "算法分析", "操作系统基础"][index], teacher: "测试教师", location: "弘远楼 A0301",
                    startSection: 1, sectionCount: 2, weekdays: [.monday], colorValue: 0x5477D9,
                    startTimeMinutes: 480, reminderMinutesBefore: nil, startWeek: 1, endWeek: 30)
            })
        }
        return nil
    }
    #endif
}

struct CourseSignature: Equatable {
    private struct Slot: Hashable {
        let teacher: String
        let location: String
        let startSection: Int
        let sectionCount: Int
        let weekdays: Set<Weekday>
        let startMinutes: Int?
        let weeks: Set<Int>
        let duration: Int?
        let dates: [Date]?
        let ends: [Date]?
        init(_ slot: CourseTimeSlot) {
            teacher = slot.teacher.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            location = slot.location.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            startSection = slot.startSection; sectionCount = slot.sectionCount; weekdays = slot.weekdays
            startMinutes = slot.startTimeMinutes
            weeks = slot.activeWeeks ?? Set((slot.startWeek ?? 1)...max(slot.startWeek ?? 1, slot.endWeek ?? 20))
            duration = slot.durationMinutes
            let sorted = slot.datedEvents?.sorted { $0.startDate < $1.startDate }
            dates = sorted?.map(\.startDate); ends = sorted?.map(\.endDate)
        }
    }
    private let name: String
    private let slots: Set<Slot>
    init(_ course: Course) {
        name = course.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        slots = Set(course.timeSlots.map(Slot.init))
    }
}
