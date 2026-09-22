import XCTest

final class BookReadingFlowTests: XCTestCase {
    @MainActor private func openProject(_ app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["阅读"].waitForExistence(timeout: 15)); app.tabBars.buttons["阅读"].tap()
        let project = app.buttons["reading-project-example/synthetic-vault-main"]
        XCTAssertTrue(project.waitForExistence(timeout: 5)); project.tap()
    }
    @MainActor private func openFile(_ path: String, app: XCUIApplication) {
        let link = app.buttons["reading-file:" + path]
        for _ in 0..<5 { if link.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 5)); link.tap()
    }
    @MainActor func testMarkdownContinuesAfterRelaunchAndReflowsAtSameChapter() {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--reset-reading"]; app.launch()
        openProject(app)
        openFile("read/夜航手记/夜航手记-原文.md", app: app)
        XCTAssertTrue(app.buttons["readingContents"].waitForExistence(timeout: 15)); app.buttons["readingContents"].tap()
        XCTAssertTrue(app.buttons["第二章 灯塔"].waitForExistence(timeout: 5)); app.buttons["第二章 灯塔"].tap()
        let progress = app.staticTexts["readingProgress"]
        let saved = expectation(for: NSPredicate(format: "label != '0%%'"), evaluatedWith: progress)
        wait(for: [saved], timeout: 6)
        XCTAssertTrue(app.webViews.staticTexts["第二章 灯塔"].firstMatch.isHittable)
        app.terminate(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["阅读"].waitForExistence(timeout: 15)); app.tabBars.buttons["阅读"].tap()
        XCTAssertTrue(app.buttons["continueReading"].waitForExistence(timeout: 5)); app.buttons["continueReading"].tap()
        XCTAssertTrue(app.buttons["readingContents"].waitForExistence(timeout: 15))
        let chapter = app.webViews.staticTexts["第二章 灯塔"].firstMatch
        let restored = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: chapter)
        wait(for: [restored], timeout: 8)
        app.buttons["readingAppearance"].tap(); app.buttons["放大"].tap(); app.buttons["完成"].tap()
        XCTAssertTrue(chapter.isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "book-resumed"; shot.lifetime = .keepAlways; add(shot)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        openFile("read/夜航手记/夜航手记-精简版.md", app: app)
        XCTAssertTrue(app.buttons["readingContents"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.webViews.staticTexts["夜航手记精简版"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.webViews.staticTexts["夜航手记精简版"].firstMatch.isHittable)
    }
    @MainActor func testPDFRestoresPageAndProjectsStaySeparate() {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--reset-reading"]; app.launch()
        openProject(app); openFile("files/夜航手记.pdf", app: app)
        XCTAssertTrue(app.buttons["pdfPage"].waitForExistence(timeout: 15))
        app.buttons["下一页"].tap(); app.buttons["下一页"].tap()
        let page = app.buttons["pdfPage"]
        let page3 = expectation(for: NSPredicate(format: "label == '第 3 / 5 页'"), evaluatedWith: page)
        wait(for: [page3], timeout: 6)
        app.terminate(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["阅读"].waitForExistence(timeout: 15)); app.tabBars.buttons["阅读"].tap()
        XCTAssertTrue(app.buttons["continueReading"].waitForExistence(timeout: 5)); app.buttons["continueReading"].tap()
        XCTAssertTrue(app.buttons["pdfPage"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons["pdfPage"].label, "第 3 / 5 页")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "pdf-resumed"; shot.lifetime = .keepAlways; add(shot)
        app.navigationBars.buttons.element(boundBy: 0).tap(); app.navigationBars.buttons.element(boundBy: 0).tap()
        let other = app.buttons["reading-project-example/synthetic-other-main"]
        XCTAssertTrue(other.waitForExistence(timeout: 5)); other.tap()
        XCTAssertTrue(app.staticTexts["example/synthetic-other"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["阅读"].isSelected)
        XCTAssertFalse(app.buttons["continueBook"].exists)
    }
}
