import XCTest
@testable import Kebiao

@MainActor
final class ReminderDiagnosticsTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: hour, minute: minute))!
    }

    private func timetable(name: String = "秋季课表") -> Timetable {
        let events = [9, 14].map { hour in
            DatedCourseEvent(startDate: date(hour), endDate: date(hour + 1))
        }
        let slot = CourseTimeSlot(teacher: "王老师", location: "A301", reminderMinutesBefore: 10,
                                  datedEvents: events)
        return Timetable(name: name, semesterStartDate: date(0), timeZoneIdentifier: "GMT",
            courses: [Course(name: "操作系统", colorValue: 0x5477D9, timeSlots: [slot])])
    }

    private func defaults() throws -> (UserDefaults, String) {
        let name = "Kebiao.ReminderDiagnosticsTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: name)), name)
    }

    private func store(_ table: Timetable, in defaults: UserDefaults, enabled: Bool = true) throws {
        let collection = TimetableCollection(timetables: [table], activeTimetableID: table.id)
        defaults.set(try JSONEncoder().encode(collection), forKey: KebiaoConfiguration.collectionStorageKey)
        defaults.set(enabled, forKey: ReminderPreferences.enabledKey)
    }

    private func scheduler(_ fake: ReminderNotificationFake, defaults: UserDefaults) -> ReminderScheduler {
        let now = date(8)
        return ReminderScheduler(client: fake.client, preferenceDefaults: defaults,
            timetableDefaults: defaults, now: { now })
    }

    func testDiagnosticsUsesActualQueueAndIgnoresUnrelatedNotifications() async throws {
        let table = timetable()
        let other = timetable(name: "旧学期")
        let settings = ReminderNotificationSettings(authorization: .provisional, alerts: .disabled, sound: .disabled)
        let pending = [
            PendingReminderNotification(identifier: "kebiao.course.\(table.id)-one", nextTriggerDate: date(13)),
            PendingReminderNotification(identifier: "kebiao.course.\(table.id)-no-date", nextTriggerDate: nil),
            PendingReminderNotification(identifier: "kebiao.course.\(other.id)-old", nextTriggerDate: date(9)),
            PendingReminderNotification(identifier: "another-feature", nextTriggerDate: date(8, 1))
        ]
        let value = ReminderDiagnostics.make(timetableID: table.id, appEnabled: false, settings: settings,
            pending: pending, recentFailure: nil, checkedAt: date(8))
        XCTAssertEqual(value.scheduledCount, 2)
        XCTAssertEqual(value.otherTimetableCount, 1)
        XCTAssertEqual(value.nextReminderDate, date(13))
        XCTAssertFalse(value.appEnabled)
        XCTAssertEqual(value.settings.authorization, .provisional)
        XCTAssertEqual(value.settings.alerts, .disabled)
        XCTAssertEqual(value.settings.sound, .disabled)
    }

    func testDeniedPermissionDoesNotScheduleOrAskAgainOnRetry() async throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let table = timetable()
        try store(table, in: defaults)
        let fake = ReminderNotificationFake(settings: .init(authorization: .denied, alerts: .disabled, sound: .disabled))
        let scheduler = scheduler(fake, defaults: defaults)
        await scheduler.reschedule(timetable: table)
        let value = await scheduler.diagnostics(timetable: table)
        let calls = await fake.authorizationCalls
        let attempts = await fake.attempts
        XCTAssertEqual(value?.settings.authorization, .denied)
        XCTAssertEqual(value?.scheduledCount, 0)
        XCTAssertNil(value?.nextReminderDate)
        XCTAssertTrue(attempts.isEmpty)
        XCTAssertEqual(calls, 0)
    }

    func testProvisionalAuthorizationSchedulesWithRealCountsAndTimeZone() async throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let table = timetable()
        try store(table, in: defaults)
        let fake = ReminderNotificationFake(settings: .init(authorization: .provisional, alerts: .disabled, sound: .disabled))
        let scheduler = scheduler(fake, defaults: defaults)
        await scheduler.reschedule(timetable: table)
        let value = await scheduler.diagnostics(timetable: table)
        let attempts = await fake.attempts
        XCTAssertEqual(value?.scheduledCount, 2)
        XCTAssertEqual(value?.nextReminderDate, date(8, 50))
        XCTAssertEqual(Set(attempts.map(\.timeZoneIdentifier)), [table.calendar.timeZone.identifier])
        XCTAssertNil(value?.recentFailure)
    }

    func testPartialAddFailureContinuesAndSuccessfulRetryClearsError() async throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let table = timetable()
        try store(table, in: defaults)
        let fake = ReminderNotificationFake()
        await fake.setFailures([1])
        await fake.setPending([PendingReminderNotification(identifier: "non-course", nextTriggerDate: date(10)),
            PendingReminderNotification(identifier: "kebiao.course.\(UUID())-old", nextTriggerDate: date(12))])
        let scheduler = scheduler(fake, defaults: defaults)
        await scheduler.reschedule(timetable: table)
        let partial = await scheduler.diagnostics(timetable: table)
        let attempts = await fake.attempts
        XCTAssertEqual(attempts.count, 2)
        XCTAssertEqual(partial?.scheduledCount, 1)
        XCTAssertEqual(partial?.otherTimetableCount, 0)
        XCTAssertEqual(partial?.recentFailure?.failedCount, 1)
        XCTAssertEqual(partial?.recentFailure?.attemptedCount, 2)
        XCTAssertTrue(partial?.recentFailure?.message.contains("模拟添加失败") == true)
        await scheduler.reschedule(timetable: table)
        let success = await scheduler.diagnostics(timetable: table)
        let pending = await fake.pendingValues
        XCTAssertEqual(success?.scheduledCount, 2)
        XCTAssertNil(success?.recentFailure)
        XCTAssertTrue(pending.contains { $0.identifier == "non-course" })
    }

    func testDisableWhileAddSuspendsRemovesLateRequestAndKeepsUnrelatedRequest() async throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let table = timetable()
        try store(table, in: defaults)
        let fake = ReminderNotificationFake()
        await fake.setPending([PendingReminderNotification(identifier: "other-feature", nextTriggerDate: date(12))])
        let gate = ReminderAsyncGate()
        let began = expectation(description: "Notification add suspended")
        await fake.pauseNextAdd(gate, began: began)
        let scheduler = scheduler(fake, defaults: defaults)
        let task = Task { await scheduler.reschedule(timetable: table) }
        await fulfillment(of: [began], timeout: 2)
        let disableTask = Task { await scheduler.disable() }
        for _ in 0..<100 where defaults.bool(forKey: ReminderPreferences.enabledKey) { await Task.yield() }
        XCTAssertFalse(defaults.bool(forKey: ReminderPreferences.enabledKey))
        await gate.open()
        await task.value
        await disableTask.value
        let value = await scheduler.diagnostics(timetable: table)
        let pending = await fake.pendingValues
        XCTAssertEqual(value?.appEnabled, false)
        XCTAssertEqual(value?.scheduledCount, 0)
        XCTAssertEqual(pending.map(\.identifier), ["other-feature"])
    }

    func testOldScheduleCannotSurviveRapidSwitchWhileAddSuspends() async throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = timetable()
        let second = timetable(name: "第二课表")
        try store(first, in: defaults)
        let fake = ReminderNotificationFake()
        let gate = ReminderAsyncGate()
        let began = expectation(description: "Old timetable add suspended")
        await fake.pauseNextAdd(gate, began: began)
        let scheduler = scheduler(fake, defaults: defaults)
        let oldTask = Task { await scheduler.reschedule(timetable: first) }
        await fulfillment(of: [began], timeout: 2)
        try store(second, in: defaults)
        let newTask = Task { await scheduler.reschedule(timetable: second) }
        await gate.open()
        await oldTask.value
        await newTask.value
        let value = await scheduler.diagnostics(timetable: second)
        let pending = await fake.pendingValues
        XCTAssertEqual(value?.scheduledCount, 2)
        XCTAssertEqual(value?.otherTimetableCount, 0)
        XCTAssertTrue(pending.allSatisfy { $0.identifier.hasPrefix("kebiao.course.\(second.id)-") })
    }

    func testDiagnosticQueryDiscardsEditedSnapshotEvenWithSameTimetableID() async throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = timetable()
        try store(first, in: defaults)
        let fake = ReminderNotificationFake()
        let gate = ReminderAsyncGate()
        let began = expectation(description: "Diagnostic pending query suspended")
        await fake.pauseNextPending(gate, began: began)
        let scheduler = scheduler(fake, defaults: defaults)
        let oldTask = Task { await scheduler.diagnostics(timetable: first) }
        await fulfillment(of: [began], timeout: 2)
        var edited = first
        edited.courses[0].name = "改名后的课程"
        try store(edited, in: defaults)
        let current = await scheduler.diagnostics(timetable: edited)
        await gate.open()
        let stale = await oldTask.value
        XCTAssertNil(stale)
        XCTAssertEqual(current?.timetableID, edited.id)
    }

    func testOlderDiagnosticQueryCannotReplaceNewerQueryForSameSnapshot() async throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let table = timetable()
        try store(table, in: defaults)
        let fake = ReminderNotificationFake()
        let gate = ReminderAsyncGate()
        let began = expectation(description: "First queue query suspended")
        await fake.pauseNextPending(gate, began: began)
        let scheduler = scheduler(fake, defaults: defaults)
        let oldTask = Task { await scheduler.diagnostics(timetable: table) }
        await fulfillment(of: [began], timeout: 2)
        await fake.setPending([PendingReminderNotification(identifier: "kebiao.course.\(table.id)-new", nextTriggerDate: date(9))])
        let newer = await scheduler.diagnostics(timetable: table)
        await gate.open()
        let older = await oldTask.value
        XCTAssertEqual(newer?.scheduledCount, 1)
        XCTAssertNil(older)
    }

    func testAuthorizationFinishingAfterDisableCannotEnableOrSchedule() async throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let table = timetable()
        try store(table, in: defaults, enabled: false)
        let fake = ReminderNotificationFake()
        let gate = ReminderAsyncGate()
        let began = expectation(description: "Permission request suspended")
        await fake.pauseAuthorization(gate, began: began)
        let scheduler = scheduler(fake, defaults: defaults)
        let permission = Task { await scheduler.requestAuthorizationAndReschedule(timetable: table) }
        await fulfillment(of: [began], timeout: 2)
        await scheduler.disable()
        await gate.open()
        let granted = await permission.value
        let attempts = await fake.attempts
        XCTAssertFalse(granted)
        XCTAssertFalse(defaults.bool(forKey: ReminderPreferences.enabledKey))
        XCTAssertTrue(attempts.isEmpty)
    }

    func testSuspendedDisableCleanupCannotRemoveReenabledScheduleWithSameIDs() async throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let table = timetable()
        try store(table, in: defaults)
        let fake = ReminderNotificationFake()
        let scheduler = scheduler(fake, defaults: defaults)
        await scheduler.reschedule(timetable: table)
        let gate = ReminderAsyncGate()
        let began = expectation(description: "Disable cleanup suspended")
        await fake.pauseNextRemove(gate, began: began)
        let disableTask = Task { await scheduler.disable() }
        await fulfillment(of: [began], timeout: 2)
        defaults.set(true, forKey: ReminderPreferences.enabledKey)
        let reenableTask = Task { await scheduler.reschedule(timetable: table) }
        await gate.open()
        await disableTask.value
        await reenableTask.value
        let value = await scheduler.diagnostics(timetable: table)
        XCTAssertEqual(value?.appEnabled, true)
        XCTAssertEqual(value?.scheduledCount, 2)
    }
}

private actor ReminderAsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

private actor ReminderNotificationFake {
    var settingsValue: ReminderNotificationSettings
    var pendingValues: [PendingReminderNotification] = []
    var attempts: [ReminderNotificationRequest] = []
    var authorizationCalls = 0
    private var failures: Set<Int> = []
    private var nextAddPause: (ReminderAsyncGate, XCTestExpectation)?
    private var nextPendingPause: (ReminderAsyncGate, XCTestExpectation)?
    private var nextRemovePause: (ReminderAsyncGate, XCTestExpectation)?
    private var authorizationPause: (ReminderAsyncGate, XCTestExpectation)?

    init(settings: ReminderNotificationSettings = .init(authorization: .authorized, alerts: .enabled, sound: .enabled)) {
        settingsValue = settings
    }

    nonisolated var client: ReminderNotificationClient {
        ReminderNotificationClient(requestAuthorization: { await self.authorize() },
            settings: { await self.settingsValue }, pending: { await self.pending() },
            add: { try await self.add($0) }, remove: { await self.remove($0) })
    }

    func setFailures(_ values: Set<Int>) { failures = values }
    func setPending(_ values: [PendingReminderNotification]) { pendingValues = values }
    func pauseNextAdd(_ gate: ReminderAsyncGate, began: XCTestExpectation) { nextAddPause = (gate, began) }
    func pauseNextPending(_ gate: ReminderAsyncGate, began: XCTestExpectation) { nextPendingPause = (gate, began) }
    func pauseNextRemove(_ gate: ReminderAsyncGate, began: XCTestExpectation) { nextRemovePause = (gate, began) }
    func pauseAuthorization(_ gate: ReminderAsyncGate, began: XCTestExpectation) { authorizationPause = (gate, began) }

    private func authorize() async -> Bool {
        authorizationCalls += 1
        if let (gate, began) = authorizationPause {
            authorizationPause = nil
            began.fulfill()
            await gate.wait()
        }
        return true
    }

    private func pending() async -> [PendingReminderNotification] {
        let result = pendingValues
        if let (gate, began) = nextPendingPause {
            nextPendingPause = nil
            began.fulfill()
            await gate.wait()
        }
        return result
    }

    private func add(_ request: ReminderNotificationRequest) async throws {
        attempts.append(request)
        let shouldFail = failures.contains(attempts.count)
        if let (gate, began) = nextAddPause {
            nextAddPause = nil
            began.fulfill()
            await gate.wait()
        }
        if shouldFail {
            throw NSError(domain: "ReminderTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "模拟添加失败"])
        }
        pendingValues.removeAll { $0.identifier == request.identifier }
        pendingValues.append(PendingReminderNotification(identifier: request.identifier, nextTriggerDate: request.fireDate))
    }

    private func remove(_ identifiers: [String]) async {
        let removed = Set(identifiers)
        if let (gate, began) = nextRemovePause {
            nextRemovePause = nil
            began.fulfill()
            await gate.wait()
        }
        pendingValues.removeAll { removed.contains($0.identifier) }
    }
}
