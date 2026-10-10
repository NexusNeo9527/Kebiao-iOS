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
        let form = app.collectionViews.firstMatch
        let permission = app.descendants(matching: .any)["reminder-permission"].firstMatch
        XCTAssertTrue(permission.waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["reminder-pending-count"].firstMatch.exists)
        capture("quality-reminder-status")
        let retry = app.buttons["reminder-reschedule"]
        reveal(retry, in: form, app: app)
        XCTAssertTrue(retry.exists)
        if retry.isEnabled { retry.tap() }
        XCTAssertFalse(app.alerts.firstMatch.exists, "Rescheduling must not request permission")
        let check = app.buttons["widget-data-check"]
        reveal(check, in: form, app: app)
        XCTAssertTrue(check.isHittable)
        check.tap()
        capture("quality-shared-data-status")
        let refresh = app.buttons["widget-request-refresh"]
        reveal(refresh, in: form, app: app)
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
        let previewScroll = app.scrollViews["import-preview-scroll"]
        let secondWeeks = app.staticTexts["import-slot-weeks-" + prefix + "202"]
        XCTAssertTrue(app.buttons["import-correct-" + courseID].waitForExistence(timeout: 15))
        reveal(secondWeeks, in: previewScroll, app: app)
        XCTAssertEqual(secondWeeks.label, "第 2、4、6 周")
        XCTAssertEqual(app.staticTexts["import-slot-time-" + prefix + "202"].label, "23:30–次日 01:30")
        capture("quality-import-all-slots")
        let expand = app.buttons["import-expand-" + prefix + "203"]
        reveal(expand, in: previewScroll, app: app)
        XCTAssertTrue(expand.isHittable)
        expand.tap()
        let lastEvent = app.staticTexts["import-event-" + prefix + "304"]
        reveal(lastEvent, in: previewScroll, app: app)
        XCTAssertTrue(lastEvent.exists)
        capture("quality-import-dated-expanded")

        let correct = app.buttons["import-correct-" + courseID]
        reveal(correct, in: previewScroll, app: app, upward: false)
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
        reveal(every, in: scroll, app: app)
        XCTAssertTrue(every.isHittable)
        every.tap()
        capture("quality-import-second-slot-correction")
        app.buttons["import-correction-save"].tap()
        reveal(secondWeeks, in: previewScroll, app: app)
        XCTAssertEqual(secondWeeks.label, "第 2–6 周")
        XCTAssertTrue(app.staticTexts["import-pdf-source-" + courseID].exists)
        capture("quality-import-corrected-preview")
        app.buttons["关闭"].tap()
        XCTAssertFalse(app.staticTexts[courseName].exists, "Canceling import must leave saved courses unchanged")
    }

    func testSmallAndMediumWidgetContentStates() {
        let app = launch("--ui-test-widget-host")
        let menu = app.buttons["widget-host-state-menu"]
        let hostScroll = app.scrollViews.firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 15))
        let states = ["正常有课", "正常无课", "尚未同步", "共享容器不可用", "数据损坏", "版本不支持"]
        let content = ["软件工程", "今天没有课程", "尚未同步课表", "共享同步不可用", "课表数据无法读取", "数据版本暂不支持"]
        for (index, state) in states.enumerated() {
            reveal(menu, in: hostScroll, app: app, upward: false)
            menu.tap()
            app.buttons[state].tap()
            XCTAssertEqual(app.staticTexts["widget-host-state"].label, state)
            let small = app.otherElements["widget-host-small"]
            reveal(small, in: hostScroll, app: app)
            XCTAssertTrue(small.exists)
            XCTAssertTrue(app.staticTexts[content[index]].firstMatch.exists)
            capture("quality-widget-small-state-\(index)")
            let medium = app.otherElements["widget-host-medium"]
            reveal(medium, in: hostScroll, app: app)
            XCTAssertTrue(medium.exists)
            capture("quality-widget-medium-state-\(index)")
        }
    }

    // SwiftUI sometimes reports an offscreen element as hittable under a fixed footer.
    // Check its rendered position before sending a tap or taking an acceptance screenshot.
    private func reveal(_ element: XCUIElement, in scroll: XCUIElement, app: XCUIApplication, upward: Bool = true) {
        for _ in 0..<24 {
            if element.exists {
                let viewport = scroll.frame
                let navigationBottom = app.navigationBars.firstMatch.frame.maxY
                var bottom = min(viewport.maxY, app.frame.maxY - 30)
                let importFooter = app.buttons["合并导入"]
                if importFooter.exists { bottom = min(bottom, importFooter.frame.minY - 12) }
                let tabs = app.tabBars.firstMatch
                if tabs.exists && tabs.frame.minY > app.frame.midY { bottom = min(bottom, tabs.frame.minY - 12) }
                let frame = element.frame
                if frame.minY >= max(viewport.minY, navigationBottom) + 4 && frame.maxY <= bottom - 4 { return }
            }
            if upward { scroll.swipeUp(velocity: .slow) }
            else { scroll.swipeDown(velocity: .slow) }
        }
        XCTFail("Element must be visible within the scroll viewport: \(element)")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
