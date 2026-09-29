import SwiftUI
import VaultCore

struct VaultSuitabilityNotice: View {
    let state: AppState
    var compact = false
    var body: some View {
        if state.vaultContentProfile.needsSuitabilityNotice && !state.vaultNotices.isDismissed(for: state.config, isSample: state.demo) {
            Section {
                if compact {
                    HStack(alignment: .top, spacing: 8) {
                        DisclosureGroup { explanation } label: { title.frame(minHeight: 44, alignment: .leading) }.font(.caption)
                        dismissButton
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .center, spacing: 8) {
                            title.font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
                            dismissButton
                        }
                        explanation
                    }
                        .padding(.vertical, 3)
                }
            }
        }
    }
    private var dismissButton: some View {
        Button { state.vaultNotices.dismiss(for: state.config, isSample: state.demo) } label: {
            Image(systemName: "xmark").font(.body).foregroundStyle(.secondary).frame(width: 44, height: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(L10n.text("Dismiss for this library"))
        .accessibilityIdentifier("dismissVaultSuitabilityNotice")
    }
    private var title: some View { Label(L10n.text("This library is mostly non-text files"), systemImage: "info.circle") }
    private var explanation: some View {
        Text(L10n.text("Vault Reader works best with Markdown notes and text-based reading. You can still browse this library and search file names, types and available metadata; attachment contents are not indexed."))
            .font(.caption).foregroundStyle(.secondary)
    }
}
