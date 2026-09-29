import XCTest

final class SearchResilienceFlowTests: XCTestCase {
    @MainActor private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "--demo", "--search-catalog-preview"]
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
}
