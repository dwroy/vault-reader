import Foundation
import VaultCore

/// Native presentation state. Never infer severity from a translated message.
struct LibraryStatus: Equatable {
    enum Kind { case updating, notUpdated, offline, authorization, rateLimited, sample, cached, attention }
    enum Action { case retry, settings, none }
    let kind: Kind
    let message: String
    let action: Action

    var shortLabel: String {
        switch kind {
        case .updating: L10n.text("Updating")
        case .notUpdated: L10n.text("Not updated")
        case .offline: L10n.text("Offline")
        case .authorization: L10n.text("Sign in")
        case .rateLimited: L10n.text("Rate limited")
        case .sample: L10n.text("Sample")
        case .cached: L10n.text("Cached")
        case .attention: L10n.text("Attention")
        }
    }
    var symbol: String {
        switch kind {
        case .updating: "arrow.trianglehead.2.clockwise.rotate.90"
        case .notUpdated: "exclamationmark.icloud"
        case .offline: "wifi.slash"
        case .authorization: "key"
        case .rateLimited: "clock.badge.exclamationmark"
        case .sample: "book.closed"
        case .cached: "internaldrive"
        case .attention: "exclamationmark.circle"
        }
    }
    var needsAttention: Bool { [.notUpdated, .offline, .authorization, .rateLimited, .attention].contains(kind) }
    static var updating: Self { Self(kind: .updating, message: L10n.text("Opened cached files. Checking for updates…"), action: .none) }
    static var sample: Self { Self(kind: .sample, message: L10n.text("Sample library · Connect your repository in Settings"), action: .settings) }
    static var missingCredential: Self { Self(kind: .authorization, message: L10n.text("No token saved for this repository. Cached files remain available."), action: .settings) }

    static func failure(_ error: Error) -> Self {
        let kind: Kind, action: Action
        switch error as? VaultError {
        case .unauthorized, .noToken, .forbidden, .invalidConfiguration:
            kind = .authorization; action = .settings
        case .rateLimited:
            kind = .rateLimited; action = .retry
        case .network(let code):
            kind = code == URLError.notConnectedToInternet.rawValue ? .offline : .notUpdated; action = .retry
        case .http, .invalidTree:
            kind = .notUpdated; action = .retry
        case .missing, .tooLarge, .corruptBlob:
            kind = .attention; action = .none
        case nil:
            if let network = error as? URLError {
                kind = network.code == .notConnectedToInternet ? .offline : .notUpdated; action = .retry
            } else { kind = .attention; action = .none }
        }
        return Self(kind: kind, message: error.localizedDescription, action: action)
    }
}
