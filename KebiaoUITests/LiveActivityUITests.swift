import XCTest

final class LiveActivityUITests: XCTestCase {
    func testPreviewActivatesAndRemainsActiveAfterReturningHome() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-live-activity"]
        app.launch()

        let status = app.staticTexts["live-activity-status"]
        let preview = app.buttons["live-activity-preview"]
        for _ in 0..<16 where !preview.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(status.waitForExistence(timeout: 15), "Live Activity status is missing")
        XCTAssertTrue(preview.isHittable, "Preview action is unavailable")
        preview.tap()
        let activated = NSPredicate(format: "label CONTAINS %@", "预览实时活动已激活")
        expectation(for: activated, evaluatedWith: status)
        waitForExpectations(timeout: 15)
        capture("live-activity-settings")

        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 10))
        // SpringBoard can enter the foreground before its Home animation finishes.
        Thread.sleep(forTimeInterval: 2)
        capture("live-activity-home-screen")
        let hierarchy = XCTAttachment(string: springboard.debugDescription)
        hierarchy.name = "live-activity-home-accessibility"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)

        app.activate()
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(status.label.contains("已激活"), "Returning home must not destroy the preview")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
