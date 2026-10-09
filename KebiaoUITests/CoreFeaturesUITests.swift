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
        let tabBarCourse = app.tabBars.buttons["课程"]
        let courseTab = tabBarCourse.exists ? tabBarCourse : app.buttons["课程"].firstMatch
        XCTAssertTrue(courseTab.waitForExistence(timeout: 5))
        courseTab.tap()
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
        let secondSlot = app.buttons["复制时段2"]
        let editorScroll = app.scrollViews["course-editor-scroll"]
        for _ in 0..<20 where !secondSlot.isHittable { editorScroll.swipeUp(velocity: .slow) }
        XCTAssertTrue(secondSlot.isHittable, "The second time slot must remain reachable on a small screen")
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

    func testBackupRestorePreviewCancelAndConfirmKeepsRecoverySnapshot() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-core", "--ui-test-backup-preview"]
        app.launch()
        let selector = app.buttons["切换或管理课表"]
        XCTAssertTrue(selector.waitForExistence(timeout: 15))
        // Persist the two fixture timetables so this test also works on a fresh simulator.
        selector.tap()
        app.buttons["备用课表"].tap()
        selector.tap()
        app.buttons["秋季课表"].tap()
        selector.tap()
        app.buttons["备份与导出"].tap()

        let previewCount = app.staticTexts["backup-restore-count"]
        for _ in 0..<6 where !previewCount.isHittable { app.swipeUp() }
        XCTAssertTrue(previewCount.waitForExistence(timeout: 5))
        XCTAssertEqual(previewCount.label, "1 张课表 · 1 门课程")
        XCTAssertTrue(app.staticTexts["恢复测试课表"].exists)
        capture("core-backup-restore-preview")
        let restore = app.buttons["完整恢复并替换现有资料"]
        for _ in 0..<6 where !restore.isHittable { app.swipeUp() }
        XCTAssertTrue(restore.isHittable)
        restore.tap()
        let confirmation = app.alerts["完整恢复这份备份？"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        capture("core-backup-restore-confirmation")
        confirmation.buttons["取消"].tap()
        XCTAssertTrue(previewCount.exists)
        let currentCount = app.staticTexts["backup-current-count"]
        for _ in 0..<6 where !currentCount.isHittable { app.swipeDown() }
        XCTAssertEqual(currentCount.label, "2 张课表 · 1 门课程")
        app.buttons["完成"].tap()
        XCTAssertTrue(selector.waitForExistence(timeout: 5))
        XCTAssertEqual(selector.value as? String, "秋季课表")

        selector.tap()
        app.buttons["备份与导出"].tap()
        for _ in 0..<6 where !restore.isHittable { app.swipeUp() }
        restore.tap()
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["完整恢复"].tap()
        XCTAssertTrue(selector.waitForExistence(timeout: 10))
        XCTAssertEqual(selector.value as? String, "恢复测试课表")
        selector.tap()
        app.buttons["备份与导出"].tap()
        let snapshot = app.buttons["backup-restore-snapshot"]
        XCTAssertTrue(snapshot.waitForExistence(timeout: 5))
        for _ in 0..<6 where !snapshot.isHittable { app.swipeDown() }
        XCTAssertTrue(snapshot.isHittable)
        XCTAssertTrue(snapshot.isEnabled)
        capture("core-backup-restore-completed")
        app.buttons["完成"].tap()
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
