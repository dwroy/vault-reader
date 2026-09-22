import XCTest
final class ReadingFlowTests: XCTestCase {
    @MainActor func testHomeWikiImageAndDirectory() throws {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.webViews.staticTexts["我的知识库"].waitForExistence(timeout: 15))
        let home = XCTAttachment(screenshot: app.screenshot()); home.name = "home"; home.lifetime = .keepAlways; add(home)
        app.webViews.links["孩子的成长记录"].tap()
        XCTAssertTrue(app.webViews.links["公园的一天"].waitForExistence(timeout: 5))
        app.webViews.links["公园的一天"].tap()
        XCTAssertTrue(app.webViews.staticTexts["公园的一天"].waitForExistence(timeout: 5))
        let image = app.webViews.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "leaf.svg")).firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5)); image.tap()
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["QLPreviewControllerView"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "image-preview"; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor func testDirectoryAndSettings() throws {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["目录"].waitForExistence(timeout: 10))
        app.tabBars.buttons["目录"].tap()
        XCTAssertTrue(app.staticTexts["生活"].waitForExistence(timeout: 5))
        app.staticTexts["生活"].tap()
        XCTAssertTrue(app.staticTexts["公园的一天.md"].waitForExistence(timeout: 5))
        app.staticTexts["公园的一天.md"].tap()
        XCTAssertTrue(app.webViews.staticTexts["公园的一天"].waitForExistence(timeout: 5))
        app.tabBars.buttons["首页"].tap()
        app.buttons["设置"].tap()
        XCTAssertTrue(app.secureTextFields["token"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "settings"; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor func testInvalidTokenShowsRecoverableError() throws {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.buttons["设置"].waitForExistence(timeout: 10)); app.buttons["设置"].tap()
        let token = app.secureTextFields["token"]
        XCTAssertTrue(token.waitForExistence(timeout: 5)); token.tap(); token.typeText("invalid-vault-reader-test-token")
        app.buttons["saveConnection"].tap()
        let error = app.staticTexts["connectionError"]
        XCTAssertTrue(error.waitForExistence(timeout: 35))
        XCTAssertTrue(error.label.contains("Token 无效或已过期"))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "invalid-token"; shot.lifetime = .keepAlways; add(shot)
    }

}
