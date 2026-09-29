import Foundation
import Observation
import VaultCore

/// Suitability guidance is dismissible per saved vault/branch and isolated from sample sessions.
@MainActor @Observable final class VaultNoticePreferences {
    @ObservationIgnored private let defaults: UserDefaults
    private static let storageKey = "dismissedVaultSuitabilityNotices"
    private var dismissed: Set<String>
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        dismissed = Set(defaults.stringArray(forKey: Self.storageKey) ?? [])
    }
    private func key(_ config: RepositoryConfig, isSample: Bool) -> String {
        MetaStore.key((isSample ? "sample:" : "repository:") + config.storageKey)
    }
    func isDismissed(for config: RepositoryConfig, isSample: Bool) -> Bool {
        dismissed.contains(key(config, isSample: isSample))
    }
    func dismiss(for config: RepositoryConfig, isSample: Bool) {
        dismissed.insert(key(config, isSample: isSample))
        defaults.set(dismissed.sorted(), forKey: Self.storageKey)
    }
    #if DEBUG
    func resetSample(for config: RepositoryConfig) {
        dismissed.remove(key(config, isSample: true))
        defaults.set(dismissed.sorted(), forKey: Self.storageKey)
    }
    #endif
}
