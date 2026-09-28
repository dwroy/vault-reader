import XCTest
@testable import VaultCore

final class LocalizationTests: XCTestCase {
    func testErrorResourcesResolveAcrossLanguages() {
        let key = "Enter a read-only token in Settings first."
        let expected = ["en": key, "zh-Hans": "请先在设置中录入只读 Token。", "ar": "أدخل أولًا رمز وصول للقراءة فقط في الإعدادات."]
        for (language, value) in expected { XCTAssertEqual(CoreL10n.text(key, language: language), value) }
        for language in ["zh-Hant", "ja", "ko", "es", "pt-BR", "fr", "de", "hi", "id"] {
            XCTAssertNotEqual(CoreL10n.text(key, language: language), key, language)
        }
    }
}
