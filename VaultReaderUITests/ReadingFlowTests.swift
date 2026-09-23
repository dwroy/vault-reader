import XCTest
final class ReadingFlowTests: XCTestCase {
    @MainActor func testDirectoryNoteWikiAndImage() throws {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.staticTexts["README.md"].waitForExistence(timeout: 15))
        app.staticTexts["README.md"].tap()
        XCTAssertTrue(app.webViews.staticTexts["我的知识库"].waitForExistence(timeout: 15))
        let home = XCTAttachment(screenshot: app.screenshot()); home.name = "directory-note"; home.lifetime = .keepAlways; add(home)
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
        XCTAssertTrue(app.tabBars.buttons["目录"].isSelected)
        XCTAssertEqual(app.tabBars.buttons.allElementsBoundByIndex.map(\.label), ["目录", "阅读", "最近", "搜索"])
        XCTAssertFalse(app.tabBars.buttons["首页"].exists)
        XCTAssertTrue(app.staticTexts["生活"].waitForExistence(timeout: 5))
        app.staticTexts["生活"].tap()
        XCTAssertTrue(app.staticTexts["公园的一天.md"].waitForExistence(timeout: 5))
        app.buttons["目录操作"].tap()
        let refresh = app.buttons["刷新"], settings = app.buttons["设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        XCTAssertLessThan(refresh.frame.minY, settings.frame.minY)
        let menu = XCTAttachment(screenshot: app.screenshot()); menu.name = "directory-menu"; menu.lifetime = .keepAlways; add(menu)
        settings.tap()
        XCTAssertTrue(app.secureTextFields["token"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["完成"].exists)
        XCTAssertFalse(app.textFields["首页"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "settings-sheet"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["完成"].tap()
        XCTAssertTrue(app.staticTexts["公园的一天.md"].waitForExistence(timeout: 5))
        app.staticTexts["公园的一天.md"].tap()
        XCTAssertTrue(app.webViews.staticTexts["公园的一天"].waitForExistence(timeout: 5))
    }
    @MainActor func testInvalidTokenShowsRecoverableError() throws {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        openSettings(app)
        let token = app.secureTextFields["token"].firstMatch
        XCTAssertTrue(token.waitForExistence(timeout: 5)); token.tap(); token.typeText("invalid-vault-reader-test-token")
        app.buttons["saveConnection"].tap()
        let error = app.staticTexts["connectionError"]
        XCTAssertTrue(error.waitForExistence(timeout: 35))
        XCTAssertTrue(error.label.contains("Token 无效或已过期"), error.label)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "invalid-token"; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor func testSearchAndRecentFiles() throws {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["搜索"].waitForExistence(timeout: 15)); app.tabBars.buttons["搜索"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("银杏")
        app.buttons["搜索正文"].tap()
        XCTAssertTrue(app.staticTexts["长文.md"].waitForExistence(timeout: 5)); app.staticTexts["长文.md"].firstMatch.tap()
        XCTAssertTrue(app.webViews.staticTexts["长文"].waitForExistence(timeout: 5))
        app.tabBars.buttons["最近"].tap()
        XCTAssertTrue(app.staticTexts["记录第 1 天"].waitForExistence(timeout: 5)); app.staticTexts["记录第 1 天"].tap()
        XCTAssertTrue(app.staticTexts["生活/公园的一天.md"].waitForExistence(timeout: 5)); app.staticTexts["生活/公园的一天.md"].tap()
        XCTAssertTrue(app.webViews.staticTexts["公园的一天"].waitForExistence(timeout: 5))
    }
    @MainActor func testHTMLPersistsAfterTerminationAndIsolatesFiles() throws {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        func open(_ name: String) {
            XCTAssertTrue(app.tabBars.buttons["目录"].waitForExistence(timeout: 15)); app.tabBars.buttons["目录"].tap()
            let file = app.staticTexts[name]
            for _ in 0..<5 { if file.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(file.waitForExistence(timeout: 5)); file.tap()
            XCTAssertTrue(app.webViews.buttons["Next page"].waitForExistence(timeout: 10))
        }
        open("阅读器.html")
        app.webViews.buttons["Reset"].tap(); app.webViews.buttons["Next page"].tap(); app.webViews.buttons["Next page"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Page 3"].waitForExistence(timeout: 5))
        // Leave enough time for WebKit's persistent storage flush before a process kill.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        open("独立阅读器.html"); app.webViews.buttons["Reset"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Page 1"].waitForExistence(timeout: 5))
        app.terminate(); app.launch(); open("阅读器.html")
        XCTAssertTrue(app.webViews.staticTexts["Page 3"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "html-restored"; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor func testSavedVaultMenuSwitchesAndReturnsOffline() throws {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.buttons["切换知识库"].waitForExistence(timeout: 15)); app.buttons["切换知识库"].tap()
        app.buttons["example/synthetic-other · main"].tap()
        XCTAssertTrue(app.staticTexts["example / synthetic-other"].waitForExistence(timeout: 10))
        app.buttons["切换知识库"].tap(); app.buttons["example/synthetic-vault · main"].tap()
        XCTAssertTrue(app.staticTexts["example / synthetic-vault"].waitForExistence(timeout: 10))
    }

    @MainActor func testGitLabSetupOffersServerAndNamespace() throws {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        openSettings(app)
        app.buttons["添加知识库"].tap()
        app.buttons["providerPicker"].tap(); app.buttons["GitLab"].tap()
        XCTAssertTrue(app.textFields["GitLab 地址"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["命名空间"].exists)
    }
    @MainActor private func openSettings(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["目录操作"].waitForExistence(timeout: 15)); app.buttons["目录操作"].tap()
        XCTAssertTrue(app.buttons["设置"].waitForExistence(timeout: 5)); app.buttons["设置"].tap()
    }

}
