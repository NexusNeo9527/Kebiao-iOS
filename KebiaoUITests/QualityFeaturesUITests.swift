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
        let firstWeeks = app.staticTexts["import-slot-weeks-" + prefix + "201"]
        let originalFirstWeeks = "第 1–3、5、7–9、11、13–15、17、19–20 周"
        let secondWeeks = app.staticTexts["import-slot-weeks-" + prefix + "202"]
        XCTAssertTrue(app.buttons["import-correct-" + courseID].waitForExistence(timeout: 15))
        reveal(secondWeeks, in: previewScroll, app: app)
        XCTAssertEqual(firstWeeks.label, originalFirstWeeks)
        XCTAssertEqual(secondWeeks.label, "第 2、4、6 周")
        XCTAssertEqual(app.staticTexts["import-slot-time-" + prefix + "202"].label, "23:30–次日 01:30")
        capture("quality-import-all-slots")
        let expand = app.buttons["import-expand-" + prefix + "203"]
        reveal(expand, in: previewScroll, app: app)
        XCTAssertTrue(expand.isHittable)
        expand.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertEqual(expand.label, "收起日期安排", "Expansion must take effect before looking for the fourth date")
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
        XCTAssertEqual(firstWeeks.label, originalFirstWeeks, "Correcting the second slot must preserve the first slot's exact weeks")
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
            let viewport = visibleViewport(in: scroll, app: app)
            guard viewport.width > 0, viewport.height > 48 else {
                XCTFail("Scroll view must have an available visible viewport: \(scroll)")
                return
            }
            var dragUp = upward
            let minimumDistance = min(CGFloat(100), viewport.height * 0.6)
            var distance = max(minimumDistance, min(CGFloat(160), viewport.height * 0.4))
            if element.exists, !element.frame.isEmpty {
                let frame = element.frame
                if frame.minY >= viewport.minY + 4 && frame.maxY <= viewport.maxY - 4 { return }
                if frame.minY < viewport.minY + 4 {
                    dragUp = false
                    distance = min(distance, max(minimumDistance, viewport.minY + 12 - frame.minY))
                } else if frame.maxY > viewport.maxY - 4 {
                    dragUp = true
                    distance = min(distance, max(minimumDistance, frame.maxY - viewport.maxY + 12))
                }
            }
            dragViewport(in: scroll, viewport: viewport, upward: dragUp, distance: distance)
        }
        XCTFail("Element must be visible within the scroll viewport: \(element)")
    }

    private func visibleViewport(in scroll: XCUIElement, app: XCUIApplication) -> CGRect {
        let viewport = scroll.frame.intersection(app.frame)
        let navigationBottom = app.navigationBars.firstMatch.frame.maxY
        let top = max(viewport.minY, navigationBottom) + 4
        var bottom = min(viewport.maxY, app.frame.maxY - 30)
        let importFooter = app.buttons["合并导入"]
        if importFooter.exists { bottom = min(bottom, importFooter.frame.minY - 12) }
        let tabs = app.tabBars.firstMatch
        if tabs.exists && tabs.frame.minY > app.frame.midY { bottom = min(bottom, tabs.frame.minY - 12) }
        return CGRect(x: viewport.minX, y: top, width: viewport.width, height: max(0, bottom - top))
    }

    private func dragViewport(in scroll: XCUIElement, viewport: CGRect, upward: Bool, distance: CGFloat) {
        let frame = scroll.frame
        let delta = upward ? distance : -distance
        // The card gutter avoids pressing a week-selection or action button before dragging.
        let gutterX = viewport.minX + 12
        let start = scroll.coordinate(withNormalizedOffset: CGVector(
            dx: (gutterX - frame.minX) / frame.width,
            dy: (viewport.midY + delta / 2 - frame.minY) / frame.height))
        let end = scroll.coordinate(withNormalizedOffset: CGVector(
            dx: (gutterX - frame.minX) / frame.width,
            dy: (viewport.midY - delta / 2 - frame.minY) / frame.height))
        // Tiny drags can rebound without scrolling; hold at the end to prevent an inertial fling.
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.15)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
