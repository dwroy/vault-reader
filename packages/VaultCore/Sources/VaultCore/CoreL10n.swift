import Foundation

/// Foundation-only localization for recoverable repository errors.
enum CoreL10n {
    static func text(_ key: String, language: String? = nil) -> String {
        // SwiftPM normalizes localized resource directory names to lowercase.
        let requested = language ?? Bundle.module.preferredLocalizations.first ?? "en"
        let code = Bundle.module.localizations.first { $0.caseInsensitiveCompare(requested) == .orderedSame } ?? "en"
        let url = Bundle.module.resourceURL?.appendingPathComponent(code + ".lproj")
        let bundle = url.flatMap(Bundle.init(url:)) ?? .module
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }
}
