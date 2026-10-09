import ActivityKit
import XCTest
@testable import Kebiao

@MainActor
final class LiveActivityTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func course(start: Date, reminder: Int? = nil, duration: Int = 100) -> Course {
        Course(name: "操作系统", teacher: "教师", location: "A301", startSection: 5,
               sectionCount: 2, weekdays: [.friday], colorValue: 0x5477D9,
               startTimeMinutes: 840, reminderMinutesBefore: reminder,
               scheduledDates: [start], durationMinutes: duration)
    }

    func testStartsBeforeReminderWindowAndWithoutNotificationPermission() async {
        let fake = FakeActivityClient()
        let controller = LiveActivityController(client: fake.client)
        let value = course(start: date(9, 14), reminder: nil)
        await controller.refresh(courses: [value], enabled: true, at: date(9, 13, 29), calendar: calendar)
        XCTAssertEqual(fake.requests.map(\.course.id), [value.id])
        XCTAssertEqual(controller.status.phase, .active)
        XCTAssertTrue(controller.status.message.contains("已激活"))
    }

    func testSelectsOngoingCourseBeforeAnUpcomingCourse() {
        let current = course(start: date(9, 13))
        let next = course(start: date(9, 14))
        let plan = LiveActivityPlan.make(courses: [next, current], at: date(9, 13, 29), calendar: calendar)
        XCTAssertEqual(plan.occurrenceToDisplay?.course.id, current.id)
    }

    func testDoesNotShowTomorrowOrMoreThanSixHoursAway() {
        let tomorrow = course(start: date(10, 0, 5))
        XCTAssertNil(LiveActivityPlan.make(courses: [tomorrow], at: date(9, 23, 55), calendar: calendar).occurrenceToDisplay)
        let distant = course(start: date(9, 14))
        XCTAssertNil(LiveActivityPlan.make(courses: [distant], at: date(9, 7, 59), calendar: calendar).occurrenceToDisplay)
        XCTAssertNotNil(LiveActivityPlan.make(courses: [distant], at: date(9, 8), calendar: calendar).occurrenceToDisplay)
    }

    func testScheduledStartDoesNotCrossMidnightOrExceedEightHours() {
        let early = course(start: date(10, 0, 5))
        let earlyOccurrence = CourseOccurrence(course: early, startDate: date(10, 0, 5), endDate: date(10, 1, 45))
        XCTAssertEqual(LiveActivityPlan.scheduledStart(for: earlyOccurrence, calendar: calendar), date(10, 0))
        let afternoon = course(start: date(9, 14))
        let normal = CourseOccurrence(course: afternoon, startDate: date(9, 14), endDate: date(9, 15, 40))
        XCTAssertEqual(LiveActivityPlan.scheduledStart(for: normal, calendar: calendar), date(9, 8))
        let long = CourseOccurrence(course: afternoon, startDate: date(9, 14), endDate: date(9, 18))
        XCTAssertEqual(LiveActivityPlan.scheduledStart(for: long, calendar: calendar), date(9, 10))
    }

    func testEndedCourseClearsExistingActivity() async {
        let value = course(start: date(9, 14))
        let fake = FakeActivityClient(existing: [handle(for: value, state: .active)])
        let controller = LiveActivityController(client: fake.client)
        await controller.refresh(courses: [value], enabled: true, at: date(9, 16), calendar: calendar)
        XCTAssertEqual(fake.endedIDs.count, 1)
        XCTAssertTrue(fake.requests.isEmpty)
        XCTAssertEqual(controller.status.phase, .idle)
    }

    func testDismissedActivityIsNotReportedAsActiveOrReused() async {
        let value = course(start: date(9, 14))
        let fake = FakeActivityClient(existing: [handle(for: value, state: .dismissed)])
        let controller = LiveActivityController(client: fake.client)
        await controller.refresh(courses: [value], enabled: true, at: date(9, 13, 29), calendar: calendar)
        XCTAssertEqual(fake.requests.count, 1)
        XCTAssertEqual(controller.status.phase, .active)
        XCTAssertFalse(LiveActivityController.isVisible(.ended))
        XCTAssertFalse(LiveActivityController.isVisible(.dismissed))
    }

    func testRefreshCannotCancelPreviewWhileItsCleanupIsSuspended() async throws {
        let value = course(start: date(9, 14))
        let fake = FakeActivityClient(existing: [handle(for: value, state: .active)])
        let controller = LiveActivityController(client: fake.client)
        let cleanupStarted = expectation(description: "Activity cleanup started")
        var cleanupContinuation: CheckedContinuation<Void, Never>?
        fake.onEnd = {
            await withCheckedContinuation { continuation in
                cleanupContinuation = continuation
                cleanupStarted.fulfill()
            }
        }
        let previewTask = Task { try await controller.preview(course: value, at: date(9, 13, 29)) }
        await fulfillment(of: [cleanupStarted], timeout: 2)
        await controller.refresh(courses: [value], enabled: true, at: date(9, 13, 29), calendar: calendar)
        XCTAssertTrue(fake.requests.isEmpty)
        cleanupContinuation?.resume()
        try await previewTask.value
        XCTAssertEqual(fake.requests.count, 1)
        XCTAssertEqual(controller.status.phase, .preview)
    }

    func testRequestFailureIsVisibleInsteadOfClaimingCreation() async {
        let value = course(start: date(9, 14))
        let fake = FakeActivityClient()
        fake.requestError = NSError(domain: "ActivityKit", code: 1,
                                    userInfo: [NSLocalizedDescriptionKey: "模拟系统启动失败"])
        let controller = LiveActivityController(client: fake.client)
        await controller.refresh(courses: [value], enabled: true, at: date(9, 13, 29), calendar: calendar)
        XCTAssertEqual(controller.status.phase, .failed)
        XCTAssertTrue(controller.status.message.contains("模拟系统启动失败"))
        XCTAssertNil(controller.status.activityID)
    }

    func testPreviewDoesNotReportSuccessWhenSystemReturnsInactiveActivity() async {
        let value = course(start: date(9, 14))
        let fake = FakeActivityClient()
        fake.requestState = .dismissed
        let controller = LiveActivityController(client: fake.client)
        do {
            try await controller.preview(course: value, at: date(9, 13, 29))
            XCTFail("An invisible activity must not report a successful preview")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("dismissed"))
        }
        XCTAssertEqual(controller.status.phase, .failed)
    }

    func testExplicitStopCancelsPreviewWithAnErrorInsteadOfEmptySuccess() async {
        let value = course(start: date(9, 14))
        let fake = FakeActivityClient(existing: [handle(for: value, state: .active)])
        let controller = LiveActivityController(client: fake.client)
        let cleanupStarted = expectation(description: "Preview cleanup started")
        var cleanupContinuation: CheckedContinuation<Void, Never>?
        fake.onEnd = {
            await withCheckedContinuation { continuation in
                cleanupContinuation = continuation
                cleanupStarted.fulfill()
            }
        }
        let previewTask = Task { try await controller.preview(course: value, at: date(9, 13, 29)) }
        await fulfillment(of: [cleanupStarted], timeout: 2)
        fake.onEnd = nil
        await controller.endAll()
        cleanupContinuation?.resume()
        do {
            try await previewTask.value
            XCTFail("A cancelled preview must throw rather than report creation")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("中断"))
        }
        XCTAssertTrue(fake.requests.isEmpty)
        XCTAssertEqual(controller.status.phase, .idle)
    }

    func testLiveActivityPreferenceIsIndependentFromNotifications() throws {
        let suite = "Kebiao.LiveActivityTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: ReminderPreferences.enabledKey)
        XCTAssertTrue(LiveActivityPreferences.isEnabled(in: defaults))
        defaults.set(false, forKey: LiveActivityPreferences.enabledKey)
        XCTAssertFalse(LiveActivityPreferences.isEnabled(in: defaults))
    }

    private func handle(for value: Course, state: ActivityState) -> LiveActivityHandle {
        let start = value.scheduledDates!.first!
        return LiveActivityHandle(id: UUID().uuidString,
            attributes: ClassActivityAttributes(courseID: value.id, courseName: value.name,
                teacher: value.teacher, location: value.location, startSection: value.startSection,
                endSection: value.endSection, startDate: start,
                endDate: start.addingTimeInterval(Double(value.resolvedDurationMinutes * 60))),
            state: state)
    }
}

@MainActor
private final class FakeActivityClient {
    var existing: [LiveActivityHandle]
    var requests: [CourseOccurrence] = []
    var endedIDs: [String] = []
    var requestState: ActivityState = .active
    var requestError: Error?
    var onEnd: (() async -> Void)?

    init(existing: [LiveActivityHandle] = []) { self.existing = existing }

    var client: LiveActivityClient {
        LiveActivityClient(authorized: { true }, activities: { self.existing }, request: { occurrence in
            if let error = self.requestError { throw error }
            self.requests.append(occurrence)
            let course = occurrence.course
            let handle = LiveActivityHandle(id: UUID().uuidString,
                attributes: ClassActivityAttributes(courseID: course.id, courseName: course.name,
                    teacher: course.teacher, location: course.location, startSection: course.startSection,
                    endSection: course.endSection, startDate: occurrence.startDate, endDate: occurrence.endDate),
                state: self.requestState)
            self.existing.append(handle)
            return handle
        }, end: { handle in
            await self.onEnd?()
            self.endedIDs.append(handle.id)
            self.existing.removeAll { $0.id == handle.id }
        })
    }
}
