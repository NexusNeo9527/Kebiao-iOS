import XCTest
@testable import Kebiao

final class TimetablePersistenceTests: XCTestCase {
    private func isolatedDefaults() -> (UserDefaults, String) {
        let name = "KebiaoPersistenceTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @MainActor func testLegacyMigrationKeepsOriginalDataAndIdentities() throws {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let id = UUID()
        let json = """
        [{"id":"\(id.uuidString)","name":"迁移课程","teacher":"林老师","location":"A101","startSection":1,"sectionCount":2,"weekdays":[2,8],"colorValue":123,"activeWeeks":[1,3,25],"startTimeMinutes":490,"reminderMinutesBefore":null}]
        """.data(using: .utf8)!
        defaults.set(json, forKey: KebiaoConfiguration.storageKey)
        let store = TimetableStore(defaults: defaults, performsSystemUpdates: false)
        XCTAssertFalse(store.isReadOnly)
        XCTAssertEqual(store.courses.first?.id, id)
        XCTAssertEqual(store.courses.first?.activeWeeks, [1, 3, 25])
        XCTAssertEqual(store.courses.first?.weekdays, [.monday, .sunday])
        XCTAssertEqual(store.activeTimetable.weekCount, 25)
        XCTAssertEqual(defaults.data(forKey: KebiaoConfiguration.storageKey), json)
        let restarted = TimetableStore(defaults: defaults, performsSystemUpdates: false)
        XCTAssertEqual(restarted.collection, store.collection)
    }

    @MainActor func testEmptyLegacyTimetableStaysEmpty() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data("[]".utf8), forKey: KebiaoConfiguration.storageKey)
        let store = TimetableStore(defaults: defaults, performsSystemUpdates: false)
        XCTAssertTrue(store.courses.isEmpty)
        XCTAssertFalse(store.isReadOnly)
    }

    @MainActor func testCorruptDataDoesNotGetOverwrittenAndRecoveryRetainsIt() throws {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let corrupt = Data("unreadable original".utf8)
        defaults.set(corrupt, forKey: KebiaoConfiguration.collectionStorageKey)
        let store = TimetableStore(defaults: defaults, performsSystemUpdates: false)
        XCTAssertTrue(store.isReadOnly)
        XCTAssertFalse(store.addTimetable(name: "不能覆盖"))
        XCTAssertEqual(defaults.data(forKey: KebiaoConfiguration.collectionStorageKey), corrupt)
        let table = Timetable(name: "恢复课表")
        let backup = TimetableCollection(timetables: [table], activeTimetableID: table.id)
        XCTAssertTrue(store.restoreBackup(backup, replaceAll: true))
        XCTAssertFalse(store.isReadOnly)
        XCTAssertEqual(defaults.data(forKey: KebiaoConfiguration.recoverySnapshotKey), corrupt)
        XCTAssertEqual(store.activeTimetable.name, "恢复课表")
    }

    @MainActor func testTargetedImportDoesNotFollowCurrentSelection() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = TimetableStore(defaults: defaults, performsSystemUpdates: false)
        let first = store.activeTimetableID
        XCTAssertTrue(store.addTimetable(name: "第二张"))
        let second = store.activeTimetableID
        XCTAssertTrue(store.importCourses([Course.samples[0]], mode: .replace, into: first))
        XCTAssertEqual(store.activeTimetableID, second)
        XCTAssertTrue(store.courses.isEmpty)
        XCTAssertEqual(store.timetable(id: first)?.courses.count, 1)
        XCTAssertTrue(store.deleteTimetable(id: first))
        XCTAssertFalse(store.deleteTimetable(id: second))
    }

    @MainActor func testInvalidBellChangeIsAtomic() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = TimetableStore(defaults: defaults, performsSystemUpdates: false)
        let before = store.collection
        let data = defaults.data(forKey: KebiaoConfiguration.collectionStorageKey)
        var draft = store.activeTimetable
        draft.sectionPeriods[0].endMinutes = draft.sectionPeriods[1].startMinutes + 1
        XCTAssertFalse(store.updateTimetable(draft))
        XCTAssertEqual(store.collection, before)
        XCTAssertEqual(defaults.data(forKey: KebiaoConfiguration.collectionStorageKey), data)
    }

    @MainActor func testFullRestoreCanBeUndone() throws {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = TimetableStore(defaults: defaults, performsSystemUpdates: false)
        let original = store.collection
        let table = Timetable(name: "备份课表")
        XCTAssertTrue(store.restoreBackup(TimetableCollection(timetables: [table], activeTimetableID: table.id), replaceAll: true))
        XCTAssertTrue(store.restorePreviousSnapshot())
        XCTAssertEqual(store.collection, original)
    }

    func testBackupRoundTripPreservesAllReferences() throws {
        var course = Course.samples[0]
        let slot = course.timeSlots[0]
        course.exceptions = [CourseException(slotID: slot.id, source: .weekly("2026-09-14"), action: .cancelled)]
        let table = Timetable(name: "完整备份", courses: [course])
        let collection = TimetableCollection(timetables: [table], activeTimetableID: table.id)
        XCTAssertEqual(try TimetableBackupService.decode(TimetableBackupService.encode(collection)), collection)
        var unknown = collection
        unknown.version = 99
        XCTAssertThrowsError(try TimetableBackupService.decode(JSONEncoder().encode(unknown)))
    }

    func testCalendarUsesActualOccurrencesAndUtf8Folding() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 8))!
        let event = DatedCourseEvent(startDate: date, endDate: date.addingTimeInterval(3600))
        let slot = CourseTimeSlot(teacher: "老师", location: "A;101,教室", datedEvents: [event])
        let course = Course(name: String(repeating: "课程", count: 50), colorValue: 123, timeSlots: [slot])
        let table = Timetable(name: "日历课表", timeZoneIdentifier: "Asia/Shanghai", courses: [course])
        let data = try TimetableBackupService.calendarData(timetable: table, from: date, through: date)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("DTSTART:20260914T000000Z"))
        XCTAssertTrue(text.contains("LOCATION:A\\;101\\,教室"))
        for line in text.components(separatedBy: "\r\n") { XCTAssertLessThanOrEqual(line.utf8.count, 75) }
        let (courses, _) = try ScheduleImportService.parseICS(data)
        XCTAssertEqual(courses.flatMap { $0.timeSlots.flatMap { $0.datedEvents ?? [] } }.map(\.startDate), [date])
    }
}
