import Foundation

/// Localizes app chrome only. Repository paths, file contents and credentials are never keys.
enum L10n {
    static let supported = ["en", "zh-Hans", "zh-Hant", "ja", "ko", "es", "pt-BR", "fr", "de", "ar", "hi", "id"]
    static var language: String {
        let requested = Bundle.main.preferredLocalizations.first ?? "en"
        return supported.first { $0.caseInsensitiveCompare(requested) == .orderedSame } ?? "en"
    }
    static func text(_ key: String, language: String? = nil) -> String {
        let code = language ?? self.language
        let path = Bundle.main.path(forResource: supported.contains(code) ? code : "en", ofType: "lproj")
        let bundle = path.flatMap(Bundle.init(path:)) ?? Bundle.main
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        // Isolate inserted filenames and service names so mixed Arabic/Latin text stays ordered.
        let values: [CVarArg] = arguments.map { argument in
            if let string = argument as? String { return "\u{2068}\(string)\u{2069}" }
            return argument
        }
        return String(format: text(key), locale: Locale.current, arguments: values)
    }
}
