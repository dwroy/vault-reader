import XCTest

final class LibraryStatusFlowTests: XCTestCase {
    @MainActor private func launch(_ status: String, largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "--demo", "--status-preview", status]
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["目录"].waitForExistence(timeout: 15))
        return app
    }
    @MainActor private func capture(_ name: String, app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor func testTimeoutDetailsAndNavigation() {
        let app = launch("timeout"), status = app.buttons["libraryStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.value as? String, "未更新")
        XCTAssertFalse(app.staticTexts["libraryStatusMessage"].exists)
        capture("compact-status-directory", app: app)
        status.tap()
        let message = app.staticTexts["libraryStatusMessage"]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertTrue(message.label.contains("连接仓库服务超时"))
        XCTAssertTrue(app.buttons["retryLibraryStatus"].exists)
        capture("compact-status-details", app: app)
        app.buttons["完成"].tap()
        app.staticTexts["生活"].tap()
        XCTAssertTrue(app.staticTexts["公园的一天.md"].waitForExistence(timeout: 5))
        XCTAssertTrue(status.exists)
        app.staticTexts["公园的一天.md"].tap()
        XCTAssertTrue(app.webViews["reader-ready"].waitForExistence(timeout: 15))
        XCTAssertTrue(status.exists)
        capture("compact-status-article", app: app)
        for tab in ["最近", "搜索", "阅读"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(status.waitForExistence(timeout: 5), tab)
        }
    }
    @MainActor func testAuthorizationOpensSettings() {
        for largeText in [false, true] {
            let app = launch("authorization", largeText: largeText)
            let status = app.buttons["libraryStatus"]
            XCTAssertTrue(status.waitForExistence(timeout: 5))
            XCTAssertEqual(status.value as? String, "待授权")
            status.tap()
            XCTAssertTrue(app.buttons["statusSettings"].waitForExistence(timeout: 5))
            for _ in 0..<6 where !app.buttons["statusSettings"].isHittable { app.swipeUp() }
            app.buttons["statusSettings"].tap()
            XCTAssertTrue(app.buttons["closeSettings"].waitForExistence(timeout: 5))
            capture(largeText ? "compact-status-large-settings" : "compact-status-settings", app: app)
            app.terminate()
        }
    }
    @MainActor func testHealthyAndLargeText() {
        var app = launch("healthy")
        XCTAssertTrue(app.staticTexts["生活"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["libraryStatus"].exists)
        capture("compact-status-healthy", app: app)
        app.terminate()
        app = launch("offline", largeText: true)
        let status = app.buttons["libraryStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.value as? String, "离线")
        XCTAssertTrue(status.isHittable)
        XCTAssertGreaterThanOrEqual(status.frame.width, 44)
        XCTAssertGreaterThanOrEqual(status.frame.height, 44)
        XCTAssertLessThanOrEqual(status.frame.maxX, app.frame.maxX)
        status.tap()
        XCTAssertTrue(app.staticTexts["libraryStatusMessage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.scrollViews.firstMatch.exists, "Accessibility-sized details must scroll")
        for _ in 0..<6 where !app.buttons["retryLibraryStatus"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["retryLibraryStatus"].isHittable, "Recovery action must stay reachable at the largest text size")
        XCTAssertTrue(app.buttons["完成"].isHittable)
        capture("compact-status-large-text", app: app)
    }
}
