import SwiftUI
import VaultCore

struct VaultSuitabilityNotice: View {
    let profile: VaultContentProfile
    var compact = false
    var body: some View {
        if profile.isMostlyNonText {
            Section {
                if compact {
                    DisclosureGroup { explanation } label: { title }.font(.caption)
                } else {
                    VStack(alignment: .leading, spacing: 6) { title.font(.subheadline.weight(.semibold)); explanation }
                        .padding(.vertical, 3)
                }
            }.accessibilityIdentifier("vaultSuitabilityNotice")
        }
    }
    private var title: some View { Label(L10n.text("This library is mostly non-text files"), systemImage: "info.circle") }
    private var explanation: some View {
        Text(L10n.text("Vault Reader works best with Markdown notes and text-based reading. You can still browse this library and search file names, types and available metadata; attachment contents are not indexed."))
            .font(.caption).foregroundStyle(.secondary)
    }
}
