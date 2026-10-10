import XCTest

final class QualityFeaturesUITests: XCTestCase {
    private func launch(_ argument: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [argument]
        app.launch()
        return app
    }

    func testReminderAndSharedDataDiagnosticsAreReachable() {
        let app = launch("--ui-test-quality-reminders")
        let permission = app.descendants(matching: .any)["reminder-permission"].firstMatch
        XCTAssertTrue(permission.waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["reminder-pending-count"].firstMatch.exists)
        capture("quality-reminder-status")
        let retry = app.buttons["reminder-reschedule"]
        for _ in 0..<6 where !retry.isHittable { app.swipeUp() }
        XCTAssertTrue(retry.isHittable)
        if retry.isEnabled { retry.tap() }
        XCTAssertFalse(app.alerts.firstMatch.exists, "Rescheduling must not request permission")
        let check = app.buttons["widget-data-check"]
        for _ in 0..<12 where !check.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(check.isHittable)
        check.tap()
        capture("quality-shared-data-status")
        let refresh = app.buttons["widget-request-refresh"]
        for _ in 0..<4 where !refresh.isHittable { app.swipeUp() }
        XCTAssertTrue(refresh.isHittable)
        refresh.tap()
        XCTAssertTrue(app.staticTexts["widget-refresh-message"].waitForExistence(timeout: 5))
        capture("quality-widget-refresh-request")
    }

    func testImportAllSlotsExpansionAndCorrectionDraft() {
        let app = launch("--ui-test-import-details")
        let prefix = "14100000-0000-0000-0000-000000000"
        let courseID = prefix + "101"
        let courseName = "数据结构与算法设计（实验、讨论与跨专业综合实践）"
        let secondWeeks = app.staticTexts["import-slot-weeks-" + prefix + "202"]
        XCTAssertTrue(app.buttons["import-correct-" + courseID].waitForExistence(timeout: 15))
        for _ in 0..<8 where !secondWeeks.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertEqual(secondWeeks.label, "第 2、4、6 周")
        XCTAssertEqual(app.staticTexts["import-slot-time-" + prefix + "202"].label, "23:30–次日 01:30")
        capture("quality-import-all-slots")
        let expand = app.buttons["import-expand-" + prefix + "203"]
        for _ in 0..<8 where !expand.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(expand.isHittable)
        expand.tap()
        let lastEvent = app.staticTexts["import-event-" + prefix + "304"]
        for _ in 0..<4 where !lastEvent.isHittable { app.swipeUp() }
        XCTAssertTrue(lastEvent.exists)
        capture("quality-import-dated-expanded")

        let correct = app.buttons["import-correct-" + courseID]
        for _ in 0..<12 where !correct.isHittable { app.swipeDown(velocity: .slow) }
        correct.tap()
        let field = app.textFields["import-correction-name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("临时")
        app.buttons["import-correction-cancel"].tap()
        XCTAssertTrue(correct.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["import-course-name-" + courseID].label.contains("临时"))
        correct.tap()
        let slot = app.otherElements["import-correction-slot-" + prefix + "202"]
        let every = slot.buttons["每周"]
        let scroll = app.scrollViews["import-correction-scroll"]
        for _ in 0..<22 where !every.isHittable { scroll.swipeUp(velocity: .slow) }
        XCTAssertTrue(every.isHittable)
        every.tap()
        capture("quality-import-second-slot-correction")
        app.buttons["import-correction-save"].tap()
        for _ in 0..<10 where !secondWeeks.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertEqual(secondWeeks.label, "第 2–6 周")
        XCTAssertTrue(app.staticTexts["import-pdf-source-" + courseID].exists)
        capture("quality-import-corrected-preview")
        app.buttons["关闭"].tap()
        XCTAssertFalse(app.staticTexts[courseName].exists, "Canceling import must leave saved courses unchanged")
    }

    func testSmallAndMediumWidgetContentStates() {
        let app = launch("--ui-test-widget-host")
        let menu = app.buttons["widget-host-state-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15))
        let states = ["正常有课", "正常无课", "尚未同步", "共享容器不可用", "数据损坏", "版本不支持"]
        for (index, state) in states.enumerated() {
            for _ in 0..<4 where !menu.isHittable { app.swipeDown() }
            menu.tap()
            app.buttons[state].tap()
            XCTAssertEqual(app.staticTexts["widget-host-state"].label, state)
            XCTAssertTrue(app.otherElements["widget-host-small"].exists)
            capture("quality-widget-small-state-\(index)")
            let medium = app.otherElements["widget-host-medium"]
            for _ in 0..<4 where !medium.isHittable { app.swipeUp() }
            XCTAssertTrue(medium.exists)
            capture("quality-widget-medium-state-\(index)")
        }
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
