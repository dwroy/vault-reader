import XCTest

final class SearchResilienceFlowTests: XCTestCase {
    @MainActor private func launch(resetNotice: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "--demo", "--search-catalog-preview"]
        if resetNotice { app.launchArguments.append("--reset-vault-notice") }
        app.launch(); return app
    }
    @MainActor func testNonTextLibraryNoticeAndImageTypeSearch() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["此库以非文本文件为主"].waitForExistence(timeout: 15))
        let directory = XCTAttachment(screenshot: app.screenshot()); directory.name = "non-text-library-guidance"; directory.lifetime = .keepAlways; add(directory)
        app.tabBars.buttons["搜索"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("图片")
        XCTAssertTrue(app.staticTexts["旅行照片.png"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["仅元信息 · 文件类型限制"].firstMatch.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "image-metadata-search"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    @MainActor func testOversizedMarkdownIsNamedAndExplained() throws {
        let app = launch()
        XCTAssertTrue(app.tabBars.buttons["搜索"].waitForExistence(timeout: 15)); app.tabBars.buttons["搜索"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("巨型")
        XCTAssertTrue(app.staticTexts["巨型笔记.md"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["仅元信息 · 文件过大"].exists)
        XCTAssertFalse(app.buttons["继续"].exists, "Excluded bodies do not create a permanent incomplete/retry state")
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "oversized-metadata-search"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    @MainActor func testDismissalHidesDirectoryAndSearchNoticeAfterRelaunch() {
        let app = launch()
        let dismiss = app.buttons["dismissVaultSuitabilityNotice"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 15)); dismiss.tap()
        XCTAssertFalse(app.staticTexts["此库以非文本文件为主"].exists)
        app.tabBars.buttons["搜索"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["dismissVaultSuitabilityNotice"].exists)
        let field = app.searchFields.firstMatch; field.tap(); field.typeText("图片")
        XCTAssertTrue(app.staticTexts["旅行照片.png"].waitForExistence(timeout: 8))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "search-after-notice-dismissal"; shot.lifetime = .keepAlways; add(shot)
        app.terminate()
        let reopened = launch(resetNotice: false)
        XCTAssertTrue(reopened.staticTexts["example / synthetic-vault"].waitForExistence(timeout: 15))
        XCTAssertFalse(reopened.buttons["dismissVaultSuitabilityNotice"].exists)
        reopened.tabBars.buttons["搜索"].tap()
        XCTAssertTrue(reopened.searchFields.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(reopened.buttons["dismissVaultSuitabilityNotice"].exists)
    }
    @MainActor func testCompactSearchNoticeCanBeDismissedWithoutExpandingIt() {
        let app = launch()
        XCTAssertTrue(app.tabBars.buttons["搜索"].waitForExistence(timeout: 15)); app.tabBars.buttons["搜索"].tap()
        let dismiss = app.buttons["dismissVaultSuitabilityNotice"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 8)); dismiss.tap()
        XCTAssertFalse(app.staticTexts["此库以非文本文件为主"].exists)
        app.tabBars.buttons["目录"].tap()
        XCTAssertFalse(app.buttons["dismissVaultSuitabilityNotice"].exists)
    }

}
