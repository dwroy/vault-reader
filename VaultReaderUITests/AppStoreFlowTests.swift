import XCTest

/// Runs against the actual Release build with no debug launch arguments.
final class AppStoreFlowTests: XCTestCase {
    @MainActor func testPublicSamplesPrivacyAndRelaunch() {
        let app = XCUIApplication(); app.launch()
        if app.buttons["目录操作"].waitForExistence(timeout: 3) {
            app.buttons["目录操作"].tap(); app.buttons["设置"].tap()
            if app.buttons["leaveSamples"].waitForExistence(timeout: 3) { app.buttons["leaveSamples"].tap() }
        }
        XCTAssertTrue(app.buttons["openSamples"].waitForExistence(timeout: 10))
        capture(app, "01-welcome")
        app.buttons["openSamples"].tap()
        XCTAssertTrue(app.staticTexts["README.md"].waitForExistence(timeout: 15))
        capture(app, "02-directory")
        app.staticTexts["README.md"].tap()
        XCTAssertTrue(app.webViews["reader-ready"].waitForExistence(timeout: 15))
        capture(app, "03-markdown")
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["目录操作"].waitForExistence(timeout: 15))
        app.buttons["阅读"].firstMatch.tap()
        let project = app.buttons["reading-project-example/synthetic-vault-main"]
        XCTAssertTrue(project.waitForExistence(timeout: 5)); project.tap()
        XCTAssertTrue(app.staticTexts["夜航手记"].waitForExistence(timeout: 10))
        capture(app, "04-reading")
        app.buttons["目录"].firstMatch.tap()
        app.buttons["目录操作"].tap(); app.buttons["设置"].tap()
        app.buttons["privacyDocument"].tap()
        XCTAssertTrue(app.staticTexts["Vault Reader 隐私政策 / Privacy Policy"].waitForExistence(timeout: 5))
        capture(app, "05-privacy")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["supportDocument"].tap()
        XCTAssertTrue(app.staticTexts["Vault Reader 使用帮助 / Support"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["leaveSamples"].tap()
        XCTAssertTrue(app.buttons["openSamples"].waitForExistence(timeout: 10))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["openSamples"].waitForExistence(timeout: 10))
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
