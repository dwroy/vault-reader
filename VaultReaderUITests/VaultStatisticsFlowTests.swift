import XCTest

final class VaultStatisticsFlowTests: XCTestCase {
    @MainActor private func capture(_ name: String, app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor func testFilesStartAtTopAndStatisticsStayAtRootBottom() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "--demo"]
        app.launch()
        XCTAssertTrue(app.staticTexts["生活"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["dwroy / synthetic-vault"].exists)
        let heading = app.staticTexts["vaultStatisticsHeading"]
        XCTAssertFalse(heading.isHittable, "Statistics must not take up the first screen")
        capture("directory-without-top-metadata", app: app)
        app.staticTexts["生活"].tap()
        XCTAssertTrue(app.staticTexts["公园的一天.md"].waitForExistence(timeout: 5))
        XCTAssertFalse(heading.exists, "Vault totals only belong at the root")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        for _ in 0..<12 where !heading.isHittable { app.swipeUp() }
        XCTAssertTrue(heading.isHittable)
        XCTAssertTrue(app.descendants(matching: .any)["vaultFileCount"].firstMatch.exists)
        capture("vault-statistics-totals", app: app)
        let lastType = app.descendants(matching: .any)["vaultFileType:svg"].firstMatch
        for _ in 0..<8 {
            if lastType.isHittable && lastType.frame.maxY < app.tabBars.firstMatch.frame.minY { break }
            app.swipeUp()
        }
        XCTAssertTrue(lastType.isHittable)
        XCTAssertLessThan(lastType.frame.maxY, app.tabBars.firstMatch.frame.minY)
        XCTAssertTrue(app.staticTexts["文件总数"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["vaultFileType:pdf"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["vaultFileType:md"].firstMatch.exists)
        capture("vault-statistics-file-types", app: app)
    }
    @MainActor func testStatisticsRemainReachableAtAccessibilityTextSize() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--demo", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["directoryActions"].waitForExistence(timeout: 15))
        let pdf = app.descendants(matching: .any)["vaultFileType:pdf"].firstMatch
        for _ in 0..<25 where !pdf.isHittable { app.swipeUp() }
        XCTAssertTrue(pdf.isHittable)
        XCTAssertLessThanOrEqual(pdf.frame.maxX, app.frame.maxX)
        capture("vault-statistics-large-text", app: app)
    }
}
