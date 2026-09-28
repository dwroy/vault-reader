import XCTest
@testable import VaultReader

final class LocalizationTests: XCTestCase {
    func testBundledLanguagesAndEnglishFallback() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDevelopmentRegion") as? String, "en")
        XCTAssertTrue(Set(L10n.supported).isSubset(of: Set(Bundle.main.localizations)))
        XCTAssertEqual(L10n.text("Settings", language: "en"), "Settings")
        XCTAssertEqual(L10n.text("Settings", language: "zh-Hans"), "设置")
        XCTAssertEqual(L10n.text("Settings", language: "ar"), "الإعدادات")
        XCTAssertEqual(L10n.text("Settings", language: "unsupported"), "Settings")
        for language in L10n.supported where language != "en" {
            XCTAssertNotEqual(L10n.text("Try sample library", language: language), "Try sample library", language)
        }
    }
    func testPDFPageFormatAcrossLanguages() {
        for language in L10n.supported {
            let format = L10n.text("Page %1$ld of %2$ld", language: language)
            let value = String(format: format, 3, 5)
            XCTAssertTrue(value.contains("3") && value.contains("5"), language)
            XCTAssertFalse(value.contains("%"), language)
        }
    }
}
