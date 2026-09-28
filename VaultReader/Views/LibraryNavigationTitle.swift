import SwiftUI

extension View {
    func libraryNavigationTitle(_ title: String, state: AppState, retry: (() async -> Void)? = nil) -> some View {
        modifier(LibraryTitleModifier(title: title, state: state, retry: retry))
    }
}

private struct LibraryTitleModifier: ViewModifier {
    let title: String
    let state: AppState
    let retry: (() async -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    func body(content: Content) -> some View {
        content.navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    // Navigation bars can cap their own Dynamic Type environment.
                    LibraryNavigationTitle(title: title, state: state, retry: retry, accessibilitySize: dynamicTypeSize.isAccessibilitySize)
                }
            }
    }
}

private struct LibraryNavigationTitle: View {
    let title: String
    let state: AppState
    let retry: (() async -> Void)?
    let accessibilitySize: Bool
    @State private var showingStatus = false
    @State private var openingSettings = false
    @Environment(\.colorScheme) private var colorScheme
    private var status: LibraryStatus? { state.isRefreshing ? .updating : state.libraryStatus }
    private var statusColor: Color {
        guard status?.needsAttention == true else { return .secondary }
        return colorScheme == .dark ? Color(red: 0.87, green: 0.71, blue: 0.42) : Color(red: 0.60, green: 0.43, blue: 0.14)
    }

    var body: some View {
        Group {
            if let status {
                ViewThatFits(in: .horizontal) {
                    if !accessibilitySize {
                        HStack(spacing: 6) {
                            // Balance the status width so short titles stay centered as state changes.
                            badge(status, text: true).hidden().accessibilityHidden(true)
                            titleText.fixedSize()
                            statusButton(status, text: true)
                        }.fixedSize(horizontal: true, vertical: false)
                    }
                    HStack(spacing: 6) {
                        titleText.layoutPriority(1)
                        statusButton(status, text: false).fixedSize()
                    }
                }
            } else { titleText }
        }
        .popover(isPresented: presentation(accessibility: false), arrowEdge: .top) {
            if let status {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label(status.shortLabel, systemImage: status.symbol).font(.headline)
                        Spacer(minLength: 8)
                        Button { showingStatus = false } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(.secondary).frame(minWidth: 44, minHeight: 44) }
                            .buttonStyle(.plain).accessibilityLabel(L10n.text("Done"))
                    }
                    details(status)
                }
                .padding(20).frame(idealWidth: 300)
                .presentationCompactAdaptation(.popover)
            }
        }
        .sheet(isPresented: presentation(accessibility: true), onDismiss: {
            if openingSettings { openingSettings = false; openSettings() }
        }) {
            NavigationStack {
                ScrollView {
                    if let status {
                        VStack(alignment: .leading, spacing: 20) {
                            Text(status.shortLabel).font(.headline)
                            details(status)
                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .navigationTitle(L10n.text("Library status")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done")) { showingStatus = false } } }
            }
        }
        .onChange(of: status) { _, value in if value == nil { showingStatus = false } }
        .onChange(of: state.config.storageKey) { _, _ in showingStatus = false }
    }
    private func presentation(accessibility: Bool) -> Binding<Bool> {
        Binding(get: { showingStatus && accessibilitySize == accessibility }, set: { if !$0 { showingStatus = false } })
    }
    @ViewBuilder private func details(_ status: LibraryStatus) -> some View {
        Text("\(state.config.owner)/\(state.config.repo) · \(state.config.branch)")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        Text(status.message).font(.callout).fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("libraryStatusMessage")
        if status.action == .retry {
            Button {
                showingStatus = false
                Task { if let retry { await retry() } else { await state.refresh() } }
            } label: { Label(L10n.text("Retry"), systemImage: "arrow.clockwise").frame(maxWidth: .infinity, minHeight: 32) }
                .buttonStyle(.bordered).disabled(!state.canRefresh)
                .accessibilityIdentifier("retryLibraryStatus")
        } else if status.action == .settings {
            Button {
                showingStatus = false
                if accessibilitySize { openingSettings = true } else { openSettings() }
            } label: { Label(L10n.text("Settings"), systemImage: "gearshape").frame(maxWidth: .infinity, minHeight: 32) }
                .buttonStyle(.bordered).accessibilityIdentifier("statusSettings")
        }
    }
    private func openSettings() { state.addingRepository = false; state.showSettings = true }
    private var titleText: some View {
        Text(title).font(.headline).lineLimit(1).truncationMode(.middle).accessibilityAddTraits(.isHeader)
    }
    private func statusButton(_ status: LibraryStatus, text: Bool) -> some View {
        Button { showingStatus = true } label: { badge(status, text: text) }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.text("Library status"))
            .accessibilityValue(status.shortLabel)
            .accessibilityHint(L10n.text("View status details"))
            .accessibilityIdentifier("libraryStatus")
    }
    private func badge(_ status: LibraryStatus, text: Bool) -> some View {
        HStack(spacing: 4) {
            if status.kind == .updating { ProgressView().controlSize(.mini) }
            else { Image(systemName: status.symbol).font(.caption) }
            if text { Text(status.shortLabel).font(.caption2).lineLimit(1).fixedSize() }
        }
        .foregroundStyle(statusColor)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
    }
}
