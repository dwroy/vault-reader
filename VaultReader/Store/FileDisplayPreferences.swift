import Foundation
import Observation

@MainActor @Observable final class FileDisplayPreferences {
    @ObservationIgnored private let defaults: UserDefaults
    var hideDotFiles: Bool {
        didSet { defaults.set(hideDotFiles, forKey: "hideDotFiles") }
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hideDotFiles = defaults.bool(forKey: "hideDotFiles")
    }
    func includes(_ path: String) -> Bool {
        !hideDotFiles || !path.split(separator: "/").contains { $0.hasPrefix(".") }
    }
}
