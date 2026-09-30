import SwiftUI
import VaultCore

struct VaultStatisticsSection: View {
    let state: AppState
    private var statistics: VaultStatistics {
        state.fileDisplay.hideDotFiles ? state.vaultStatisticsHidingDotFiles : state.vaultStatistics
    }
    var body: some View {
        Section {
            LabeledContent(L10n.text("Total files"), value: statistics.fileCount.formatted())
                .accessibilityIdentifier("vaultFileCount")
            LabeledContent(L10n.text("Folders"), value: statistics.folderCount.formatted())
            LabeledContent(L10n.text(statistics.unknownSizeCount == 0 ? "Total size" : "Known size"), value: size(bytes: statistics.knownBytes, count: statistics.fileCount, unknown: statistics.unknownSizeCount, qualifyKnown: false))
            LabeledContent(L10n.text("Branch"), value: state.config.branch)
        } header: {
            Text(L10n.text("Vault statistics")).accessibilityIdentifier("vaultStatisticsHeading")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(state.config.owner) / \(state.config.repo)")
                Text(L10n.text(state.fileDisplay.hideDotFiles ? "Hidden dotfiles are excluded." : "Includes hidden dotfiles."))
                if statistics.unknownSizeCount > 0 {
                    Text(L10n.format("Sizes unavailable for %1$ld files.", statistics.unknownSizeCount))
                }
            }
        }
        if !statistics.fileTypes.isEmpty {
            Section(L10n.text("Files by type")) {
                ForEach(statistics.fileTypes) { type in
                    LabeledContent {
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(type.fileCount.formatted()).monospacedDigit()
                            Text(size(bytes: type.knownBytes, count: type.fileCount, unknown: type.unknownSizeCount))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } label: {
                        Text(type.ext.isEmpty ? L10n.text("No extension") : "." + type.ext)
                            .lineLimit(nil)
                    }
                    .accessibilityIdentifier("vaultFileType:" + type.ext)
                }
            }
        }
    }
    private func size(bytes: Int64, count: Int, unknown: Int, qualifyKnown: Bool = true) -> String {
        if count > 0 && unknown == count { return L10n.text("Size unavailable") }
        let value = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        return unknown > 0 && qualifyKnown ? L10n.format("%1$@ known", value) : value
    }
}
