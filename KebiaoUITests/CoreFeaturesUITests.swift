import XCTest

final class CoreFeaturesUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-core"]
        app.launch()
        return app
    }

    func testSwitchTimetablesAndOpenIndependentSettings() {
        let app = launch()
        let selector = app.buttons["切换或管理课表"]
        XCTAssertTrue(selector.waitForExistence(timeout: 15))
        selector.tap()
        app.buttons["备用课表"].tap()
        XCTAssertEqual(selector.value as? String, "备用课表")
        selector.tap()
        app.buttons["课表设置"].tap()
        let name = app.textFields["timetable-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "备用课表")
        capture("core-timetable-settings")
        app.buttons["取消"].tap()
        selector.tap()
        app.buttons["秋季课表"].tap()
        XCTAssertEqual(selector.value as? String, "秋季课表")
        capture("core-timetable-switch")
    }

    func testEditingSharedNamePreservesExactWeeksAndMultipleSlots() {
        let app = launch()
        app.tabBars.buttons["课程"].tap()
        app.staticTexts["多时段测试课程"].tap()
        let field = app.textFields["输入课程名称"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["时段 1"].exists)
        let firstWeek = app.buttons.matching(identifier: "第1周").firstMatch
        let secondWeek = app.buttons.matching(identifier: "第2周").firstMatch
        for _ in 0..<8 where !firstWeek.isHittable { app.swipeUp() }
        XCTAssertTrue(firstWeek.isSelected)
        XCTAssertFalse(secondWeek.isSelected)
        for _ in 0..<8 where !field.isHittable { app.swipeDown() }
        field.tap()
        field.typeText("校正")
        let editedName = field.value as? String ?? "多时段测试课程校正"
        app.buttons["保存"].tap()
        let changed = app.staticTexts[editedName]
        XCTAssertTrue(changed.waitForExistence(timeout: 5))
        changed.tap()
        for _ in 0..<8 where !firstWeek.isHittable { app.swipeUp() }
        XCTAssertTrue(firstWeek.waitForExistence(timeout: 5))
        XCTAssertTrue(firstWeek.isSelected)
        XCTAssertFalse(secondWeek.isSelected)
        for _ in 0..<12 where !app.staticTexts["时段 2"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["时段 2"].isHittable)
        capture("core-multiple-slots-and-weeks")
        app.buttons["取消"].tap()
    }

    func testBackupAndCalendarExportPreviewIsReachable() {
        let app = launch()
        app.buttons["切换或管理课表"].tap()
        app.buttons["备份与导出"].tap()
        XCTAssertTrue(app.buttons["backup-export"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["backup-import"].exists)
        for _ in 0..<4 where !app.buttons["calendar-export"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["calendar-export"].isHittable)
        capture("core-backup-calendar-preview")
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["切换或管理课表"].waitForExistence(timeout: 5))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
