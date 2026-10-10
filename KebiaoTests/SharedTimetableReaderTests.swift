import XCTest
@testable import Kebiao

final class SharedTimetableReaderTests: XCTestCase {
    private func isolatedDefaults() -> (UserDefaults, String) {
        let name = "SharedTimetableReaderTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }
    private func reader(_ defaults: UserDefaults) -> SharedTimetableReader {
        SharedTimetableReader(defaults: defaults, sharedContainerAvailable: true)
    }
    private func collection(courses: [Course] = []) -> TimetableCollection {
        TimetableCollection(timetables: [Timetable(name: "共享课表", courses: courses)])
    }
    private func seed(_ collection: TimetableCollection, in defaults: UserDefaults) throws -> Data {
        let data = try JSONEncoder().encode(collection)
        defaults.set(data, forKey: KebiaoConfiguration.collectionStorageKey)
        return data
    }

    func testUnavailableContainerDoesNotPretendSuiteIsAvailable() throws {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        _ = try seed(collection(courses: [Course.samples[0]]), in: defaults)
        let result = SharedTimetableReader(defaults: defaults, sharedContainerAvailable: false).read()
        XCTAssertEqual(result.state, .containerUnavailable)
        XCTAssertNil(result.timetable)
        XCTAssertEqual(SharedTimetableReader(defaults: nil, sharedContainerAvailable: true).read().state, .containerUnavailable)
    }

    func testMissingDataIsNotSyncedAndDoesNotSeedSamples() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(reader(defaults).read().state, .notSynced)
        XCTAssertNil(defaults.object(forKey: KebiaoConfiguration.collectionStorageKey))
        XCTAssertNil(defaults.object(forKey: KebiaoConfiguration.storageKey))
    }

    func testValidEmptyCollectionIsReadableRatherThanMissing() throws {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let original = collection()
        _ = try seed(original, in: defaults)
        let result = reader(defaults).read()
        XCTAssertEqual(result.state, .empty)
        XCTAssertTrue(result.state.isReadable)
        XCTAssertEqual(result.collection, original)
        XCTAssertNil(result.updatedAt)
    }

    func testWrongTypeV2NeverFallsBackToValidLegacy() throws {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("invalid v2 original", forKey: KebiaoConfiguration.collectionStorageKey)
        defaults.set(try JSONEncoder().encode([Course.samples[0]]), forKey: KebiaoConfiguration.storageKey)
        let result = reader(defaults).read()
        XCTAssertEqual(result.state, .corrupt)
        XCTAssertNil(result.timetable)
        XCTAssertEqual(defaults.string(forKey: KebiaoConfiguration.collectionStorageKey), "invalid v2 original")
    }

    func testCorruptV2NeverFallsBackToValidLegacyOrChangesBytes() throws {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let invalid = Data("unreadable v2".utf8)
        defaults.set(invalid, forKey: KebiaoConfiguration.collectionStorageKey)
        defaults.set(try JSONEncoder().encode([Course.samples[0]]), forKey: KebiaoConfiguration.storageKey)
        XCTAssertEqual(reader(defaults).read().state, .corrupt)
        XCTAssertEqual(defaults.data(forKey: KebiaoConfiguration.collectionStorageKey), invalid)
    }

    func testUnknownVersionIsReportedBeforeDecodingFuturePayloadShape() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let future = Data("{\"version\":99,\"futureShape\":true}".utf8)
        defaults.set(future, forKey: KebiaoConfiguration.collectionStorageKey)
        defaults.set(Data("[]".utf8), forKey: KebiaoConfiguration.storageKey)
        XCTAssertEqual(reader(defaults).read().state, .unsupportedVersion(99))
        XCTAssertEqual(defaults.data(forKey: KebiaoConfiguration.collectionStorageKey), future)
    }

    func testDecodableButInvalidCollectionIsCorrupt() throws {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        var invalid = collection()
        invalid.activeTimetableID = UUID()
        _ = try seed(invalid, in: defaults)
        XCTAssertEqual(reader(defaults).read().state, .corrupt)
    }

    func testLegacyCompatibilityRequiresMissingV2AndRetainsIdentities() throws {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        var course = Course.samples[0]
        course.activeWeeks = [1, 3, 27]
        let data = try JSONEncoder().encode([course])
        defaults.set(data, forKey: KebiaoConfiguration.storageKey)
        let result = reader(defaults).read()
        XCTAssertEqual(result.state, .ready)
        XCTAssertEqual(result.source, .legacy)
        XCTAssertEqual(result.timetable?.courses.first, course)
        XCTAssertEqual(result.timetable?.weekCount, 30)
        XCTAssertNil(result.updatedAt)
        XCTAssertNil(defaults.object(forKey: KebiaoConfiguration.collectionStorageKey))
        XCTAssertEqual(defaults.data(forKey: KebiaoConfiguration.storageKey), data)
    }

    func testEmptyLegacyIsReadableAndInvalidLegacyIsPreserved() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data("[]".utf8), forKey: KebiaoConfiguration.storageKey)
        XCTAssertEqual(reader(defaults).read().state, .empty)
        let invalid = Data("not legacy json".utf8)
        defaults.set(invalid, forKey: KebiaoConfiguration.storageKey)
        XCTAssertEqual(reader(defaults).read().state, .corrupt)
        XCTAssertEqual(defaults.data(forKey: KebiaoConfiguration.storageKey), invalid)
        defaults.set(12, forKey: KebiaoConfiguration.storageKey)
        XCTAssertEqual(reader(defaults).read().state, .corrupt)
        XCTAssertEqual(defaults.integer(forKey: KebiaoConfiguration.storageKey), 12)
    }

    func testMatchingMetadataUsesHashOfRawStoredData() throws {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let data = try JSONEncoder().encode(collection(courses: [Course.samples[0]]))
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        try SharedTimetablePersistence.write(data, to: defaults, at: date)
        let metadata = try JSONDecoder().decode(TimetableSyncMetadata.self,
            from: XCTUnwrap(defaults.data(forKey: KebiaoConfiguration.syncMetadataKey)))
        XCTAssertEqual(metadata.dataSHA256, TimetableSyncMetadata.digest(data))
        XCTAssertEqual(metadata.version, 1)
        XCTAssertEqual(reader(defaults).read().updatedAt, date)
        // Hashing identical decoded content with different raw whitespace must not validate stale metadata.
        defaults.set(Data([0x20]) + data, forKey: KebiaoConfiguration.collectionStorageKey)
        let changed = reader(defaults).read()
        XCTAssertEqual(changed.state, .ready)
        XCTAssertNil(changed.updatedAt)
    }

    func testDataFirstMetadataLaterIntermediateStateStillReadsNewCourses() throws {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        try SharedTimetablePersistence.write(JSONEncoder().encode(collection()), to: defaults,
            at: Date(timeIntervalSince1970: 1_790_000_000))
        let replacement = collection(courses: [Course.samples[0]])
        let newData = try seed(replacement, in: defaults)
        let intermediate = reader(defaults).read()
        XCTAssertEqual(intermediate.collection, replacement)
        XCTAssertEqual(intermediate.state, .ready)
        XCTAssertNil(intermediate.updatedAt)
        let newDate = Date(timeIntervalSince1970: 1_790_000_500)
        defaults.set(try JSONEncoder().encode(TimetableSyncMetadata(data: newData, writtenAt: newDate)),
            forKey: KebiaoConfiguration.syncMetadataKey)
        XCTAssertEqual(reader(defaults).read().updatedAt, newDate)
    }

    func testMissingCorruptWrongTypeAndUnknownMetadataDoNotInvalidateTimetable() throws {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let original = collection(courses: [Course.samples[0]])
        let data = try seed(original, in: defaults)
        let invalidValues: [Any] = [Data("broken metadata".utf8), "wrong type",
            Data("{\"version\":99,\"writtenAt\":0,\"dataSHA256\":\"\(TimetableSyncMetadata.digest(data))\"}".utf8)]
        for value in invalidValues {
            defaults.set(value, forKey: KebiaoConfiguration.syncMetadataKey)
            let result = reader(defaults).read()
            XCTAssertEqual(result.collection, original)
            XCTAssertEqual(result.state, .ready)
            XCTAssertNil(result.updatedAt)
        }
    }

    @MainActor func testStoreWrongTypedV2IsReadOnlyAndNeverMigratesOrSeeds() throws {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("wrong type retained", forKey: KebiaoConfiguration.collectionStorageKey)
        let legacy = try JSONEncoder().encode([Course.samples[0]])
        defaults.set(legacy, forKey: KebiaoConfiguration.storageKey)
        let store = TimetableStore(defaults: defaults, performsSystemUpdates: false)
        XCTAssertTrue(store.isReadOnly)
        XCTAssertFalse(store.save(Course.samples[0]))
        XCTAssertEqual(defaults.string(forKey: KebiaoConfiguration.collectionStorageKey), "wrong type retained")
        XCTAssertEqual(defaults.data(forKey: KebiaoConfiguration.storageKey), legacy)
        XCTAssertNil(defaults.object(forKey: KebiaoConfiguration.syncMetadataKey))
        XCTAssertNotNil(store.originalData)
    }

    @MainActor func testStoreMigrationWritesMatchingMetadataAndRepeatedLaunchDoesNotRestamp() throws {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let legacy = try JSONEncoder().encode([Course.samples[0]])
        defaults.set(legacy, forKey: KebiaoConfiguration.storageKey)
        let store = TimetableStore(defaults: defaults, performsSystemUpdates: false)
        let first = reader(defaults).read()
        XCTAssertEqual(first.collection, store.collection)
        XCTAssertNotNil(first.updatedAt)
        let metadata = defaults.data(forKey: KebiaoConfiguration.syncMetadataKey)
        let restarted = TimetableStore(defaults: defaults, performsSystemUpdates: false)
        XCTAssertEqual(restarted.collection, store.collection)
        XCTAssertEqual(defaults.data(forKey: KebiaoConfiguration.syncMetadataKey), metadata)
        XCTAssertEqual(defaults.data(forKey: KebiaoConfiguration.storageKey), legacy)
    }

    @MainActor func testStoreSaveAndRestoreStampCurrentBytesWithoutChangingBackupSchema() throws {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = TimetableStore(defaults: defaults, performsSystemUpdates: false)
        XCTAssertNotNil(reader(defaults).read().updatedAt)
        XCTAssertTrue(store.addTimetable(name: "新课表"))
        XCTAssertEqual(reader(defaults).read().collection, store.collection)
        XCTAssertNotNil(reader(defaults).read().updatedAt)
        let backup = collection()
        let beforeRestore = defaults.data(forKey: KebiaoConfiguration.collectionStorageKey)
        XCTAssertTrue(store.restoreBackup(backup, replaceAll: true))
        let restored = reader(defaults).read()
        XCTAssertEqual(restored.collection, backup)
        XCTAssertNotNil(restored.updatedAt)
        XCTAssertEqual(defaults.data(forKey: KebiaoConfiguration.recoverySnapshotKey), beforeRestore)
        let backupObject = try XCTUnwrap(JSONSerialization.jsonObject(with: TimetableBackupService.encode(backup)) as? [String: Any])
        XCTAssertEqual(Set(backupObject.keys), ["format", "version", "exportedAt", "collection"])
        let collectionObject = try XCTUnwrap(backupObject["collection"] as? [String: Any])
        XCTAssertEqual(Set(collectionObject.keys), ["version", "timetables", "activeTimetableID"])
    }

    @MainActor func testOldV2WithoutSidecarStaysValidAndUntouchedUntilSave() throws {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let original = collection(courses: [Course.samples[0]])
        let data = try seed(original, in: defaults)
        let store = TimetableStore(defaults: defaults, performsSystemUpdates: false)
        XCTAssertEqual(store.collection, original)
        XCTAssertNil(reader(defaults).read().updatedAt)
        XCTAssertNil(defaults.object(forKey: KebiaoConfiguration.syncMetadataKey))
        XCTAssertEqual(defaults.data(forKey: KebiaoConfiguration.collectionStorageKey), data)
        XCTAssertTrue(store.selectTimetable(id: store.activeTimetableID))
        XCTAssertNotNil(reader(defaults).read().updatedAt)
    }

    @MainActor func testFailedSaveDoesNotChangeDataOrSyncMetadata() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = TimetableStore(defaults: defaults, performsSystemUpdates: false)
        let originalData = defaults.data(forKey: KebiaoConfiguration.collectionStorageKey)
        let originalMetadata = defaults.data(forKey: KebiaoConfiguration.syncMetadataKey)
        var invalid = store.activeTimetable
        invalid.sectionPeriods[0].endMinutes = invalid.sectionPeriods[0].startMinutes
        XCTAssertFalse(store.updateTimetable(invalid))
        XCTAssertEqual(defaults.data(forKey: KebiaoConfiguration.collectionStorageKey), originalData)
        XCTAssertEqual(defaults.data(forKey: KebiaoConfiguration.syncMetadataKey), originalMetadata)
    }

    @MainActor func testWrongTypedLegacyDoesNotSeedAndRetainsOriginal() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("retained wrong legacy", forKey: KebiaoConfiguration.storageKey)
        let store = TimetableStore(defaults: defaults, performsSystemUpdates: false)
        XCTAssertTrue(store.isReadOnly)
        XCTAssertEqual(defaults.string(forKey: KebiaoConfiguration.storageKey), "retained wrong legacy")
        XCTAssertNil(defaults.object(forKey: KebiaoConfiguration.collectionStorageKey))
        XCTAssertNil(defaults.object(forKey: KebiaoConfiguration.syncMetadataKey))
        XCTAssertNotNil(store.originalData)
    }

    func testSharedWidgetContentKeepsOvernightAndSameDayEventsInTableTimeZone() throws {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let parser = ISO8601DateFormatter()
        let overnightStart = parser.date(from: "2026-10-09T15:00:00Z")!
        let query = parser.date(from: "2026-10-09T16:30:00Z")! // October 10 00:30 in Shanghai.
        let overnight = DatedCourseEvent(startDate: overnightStart, endDate: overnightStart.addingTimeInterval(7200))
        let morning = DatedCourseEvent(startDate: query.addingTimeInterval(3600), endDate: query.addingTimeInterval(7200))
        let afternoon = DatedCourseEvent(startDate: query.addingTimeInterval(36000), endDate: query.addingTimeInterval(39600))
        let course = Course(name: "日期课程", colorValue: 123, timeSlots: [CourseTimeSlot(datedEvents: [overnight, morning, afternoon])])
        let table = Timetable(name: "时区课表", timeZoneIdentifier: "Asia/Shanghai", courses: [course])
        _ = try seed(TimetableCollection(timetables: [table]), in: defaults)
        let entry = TodayWidgetContentEntry(date: query, snapshot: reader(defaults).read())
        XCTAssertEqual(entry.calendar.timeZone.identifier, "Asia/Shanghai")
        XCTAssertEqual(entry.occurrences.map(\.source), [.dated(overnight.id), .dated(morning.id), .dated(afternoon.id)])
        XCTAssertEqual(Set(entry.occurrences.map(\.id)).count, 3)
    }
}
