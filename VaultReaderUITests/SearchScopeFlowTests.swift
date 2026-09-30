import XCTest

final class SearchScopeFlowTests: XCTestCase {
    @MainActor func testProjectTitlesAndMultiVaultSearchKeepsSelectionOnReturn() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "--demo"]
        app.launch()
        XCTAssertTrue(app.navigationBars["synthetic-vault"].waitForExistence(timeout: 15))
        let directory = XCTAttachment(screenshot: app.screenshot()); directory.name = "project-directory-title"; directory.lifetime = .keepAlways; add(directory)
        app.tabBars.buttons["最近"].tap()
        XCTAssertTrue(app.navigationBars["synthetic-vault"].waitForExistence(timeout: 5))
        app.tabBars.buttons["搜索"].tap()
        let picker = app.buttons["searchVaultPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5)); picker.tap()
        let first = app.buttons["searchVault:synthetic-vault"], second = app.buttons["searchVault:synthetic-other"]
        XCTAssertEqual(first.value as? String, "已勾选")
        XCTAssertEqual(second.value as? String, "未勾选")
        second.tap()
        let selection = XCTAttachment(screenshot: app.screenshot()); selection.name = "vault-checkbox-selection"; selection.lifetime = .keepAlways; add(selection)
        app.buttons["完成"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("README")
        let firstHit = app.descendants(matching: .any)["searchResult:synthetic-vault:README.md"].firstMatch
        let secondHit = app.descendants(matching: .any)["searchResult:synthetic-other:README.md"].firstMatch
        XCTAssertTrue(firstHit.waitForExistence(timeout: 8)); XCTAssertTrue(secondHit.waitForExistence(timeout: 8))
        field.typeText("\n")
        let results = XCTAttachment(screenshot: app.screenshot()); results.name = "multi-vault-search"; results.lifetime = .keepAlways; add(results)
        secondHit.tap()
        XCTAssertTrue(app.webViews.staticTexts["第二个知识库"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.webViews.staticTexts["我的知识库"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "README")
        picker.tap(); XCTAssertEqual(second.value as? String, "已勾选")
        second.tap(); app.buttons["完成"].tap()
        XCTAssertTrue(firstHit.waitForExistence(timeout: 5)); XCTAssertFalse(secondHit.exists)
        app.tabBars.buttons["目录"].tap()
        XCTAssertTrue(app.navigationBars["synthetic-vault"].waitForExistence(timeout: 5), "Reading a search result must not switch the active vault")
    }
}
