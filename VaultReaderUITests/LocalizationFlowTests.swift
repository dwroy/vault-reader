import XCTest

/// Uses only the public sample entry and Apple's per-launch locale arguments, also in Release.
final class LocalizationFlowTests: XCTestCase {
    private let languages: [(String, String, String, String)] = [
        ("en", "Try sample library", "Files", "Reading"),
        ("zh-Hans", "体验示例知识库", "目录", "阅读"),
        ("zh-Hant", "體驗示例知識庫", "目錄", "閱讀"),
        ("ja", "サンプルライブラリを試す", "ファイル", "読書"),
        ("ko", "예제 라이브러리 사용해 보기", "파일", "읽기"),
        ("es", "Probar biblioteca de ejemplo", "Archivos", "Lectura"),
        ("pt-BR", "Testar biblioteca de exemplo", "Arquivos", "Leitura"),
        ("fr", "Essayer la bibliothèque d’exemple", "Fichiers", "Lecture"),
        ("de", "Beispielbibliothek ausprobieren", "Dateien", "Lesen"),
        ("ar", "تجربة المكتبة النموذجية", "الملفات", "القراءة"),
        ("hi", "नमूना लाइब्रेरी आज़माएँ", "फ़ाइलें", "पढ़ें"),
        ("id", "Coba pustaka contoh", "Berkas", "Bacaan")
    ]
    @MainActor private func launch(_ language: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", language.replacingOccurrences(of: "-", with: "_")]
        app.launch()
        if app.buttons["directoryActions"].waitForExistence(timeout: 3) {
            app.buttons["directoryActions"].tap(); app.buttons["openSettings"].tap()
            XCTAssertTrue(app.buttons["leaveSamples"].waitForExistence(timeout: 5))
            app.buttons["leaveSamples"].tap()
        }
        XCTAssertTrue(app.buttons["openSamples"].waitForExistence(timeout: 12))
        return app
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        // Accessibility can be ready before the first composited simulator frame.
        Thread.sleep(forTimeInterval: 0.8)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
    @MainActor func testEveryLanguageOpensPublicSamplesAndSettings() {
        for (language, sample, files, _) in languages {
            let app = launch(language)
            XCTAssertEqual(app.buttons["openSamples"].label, sample, language)
            XCTAssertTrue(app.buttons["openSamples"].isHittable, language)
            capture(app, language + "-01-welcome")
            app.buttons["openSamples"].tap()
            XCTAssertTrue(app.buttons["directoryActions"].waitForExistence(timeout: 12))
            XCTAssertTrue(app.buttons[files].firstMatch.exists, language)
            app.buttons["directoryActions"].tap(); app.buttons["openSettings"].tap()
            XCTAssertTrue(app.buttons["privacyDocument"].waitForExistence(timeout: 5))
            capture(app, language + "-settings")
            app.buttons["leaveSamples"].tap(); app.terminate()
        }
        let fallback = launch("sw-KE")
        XCTAssertEqual(fallback.buttons["openSamples"].label, "Try sample library")
        fallback.terminate()
    }
    @MainActor func testEnglishReadingAndResume() { readingFlow(language: "en") }
    @MainActor func testArabicReadingDirectionAndResume() { readingFlow(language: "ar") }
    @MainActor func testHindiDocumentGlyphs() {
        let app = launch("hi")
        app.buttons["openSamples"].tap()
        XCTAssertTrue(app.staticTexts["Notes"].waitForExistence(timeout: 12))
        app.staticTexts["Notes"].tap(); app.staticTexts["नमस्ते.md"].tap()
        XCTAssertTrue(app.webViews["reader-ready"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.webViews.staticTexts["नमस्ते"].exists)
        capture(app, "hi-prose-and-code")
        app.terminate()
    }
    @MainActor private func readingFlow(language: String) {
        let app = launch(language)
        let isArabic = language == "ar", files = isArabic ? "الملفات" : "Files", reading = isArabic ? "القراءة" : "Reading"
        capture(app, language + "-01-welcome")
        app.buttons["openSamples"].tap()
        XCTAssertTrue(app.staticTexts["README.md"].waitForExistence(timeout: 12))
        capture(app, language + "-02-directory")
        if isArabic, app.tabBars.buttons[files].exists {
            XCTAssertGreaterThan(app.tabBars.buttons[files].frame.midX, app.tabBars.buttons[reading].frame.midX)
        }
        app.staticTexts["README.md"].tap()
        XCTAssertTrue(app.webViews["reader-ready"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.webViews.staticTexts["Your knowledge, ready to read"].exists)
        capture(app, language + "-03-markdown")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        if isArabic {
            app.staticTexts["Notes"].tap(); app.staticTexts["مرحبا.md"].tap()
            XCTAssertTrue(app.webViews["reader-ready"].waitForExistence(timeout: 12))
            XCTAssertTrue(app.webViews.staticTexts["مرحبًا"].exists)
            capture(app, "ar-prose-and-code")
        } else {
            for _ in 0..<4 { if app.staticTexts["Reader.html"].exists && app.staticTexts["Reader.html"].isHittable { break }; app.swipeUp() }
            app.staticTexts["Reader.html"].tap()
            XCTAssertTrue(app.webViews.staticTexts["Independent HTML reader"].waitForExistence(timeout: 12))
            app.webViews.buttons["Next page"].tap()
            capture(app, "en-html")
        }
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["directoryActions"].waitForExistence(timeout: 12))
        app.buttons[reading].firstMatch.tap()
        app.buttons["reading-project-example/synthetic-vault-main"].tap()
        XCTAssertTrue(app.buttons["reading-book:Night Voyage"].waitForExistence(timeout: 8))
        capture(app, language + "-04-reading")
        app.buttons["reading-book:Night Voyage"].tap()
        app.buttons["reading-file:files/Night Voyage.pdf"].tap()
        XCTAssertTrue(app.buttons["pdfPage"].waitForExistence(timeout: 12))
        let previous = app.buttons[isArabic ? "الصفحة السابقة" : "Previous page"]
        for _ in 0..<4 { if previous.isEnabled { previous.tap() } }
        app.buttons[isArabic ? "الصفحة التالية" : "Next page"].tap()
        let page = app.buttons["pdfPage"]
        let savedPage = page.label
        XCTAssertTrue(savedPage.contains("2") || savedPage.contains("٢"))
        capture(app, language + "-pdf")
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["directoryActions"].waitForExistence(timeout: 12))
        app.buttons[reading].firstMatch.tap(); app.buttons["reading-project-example/synthetic-vault-main"].tap()
        app.buttons["reading-book:Night Voyage"].tap(); app.buttons["reading-file:files/Night Voyage.pdf"].tap()
        XCTAssertTrue(app.buttons["pdfPage"].waitForExistence(timeout: 12))
        XCTAssertEqual(app.buttons["pdfPage"].label, savedPage)
        app.terminate()
    }
}
