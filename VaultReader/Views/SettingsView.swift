import VaultCore
import SwiftUI

struct SettingsView: View {
    let state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var config = RepositoryConfig()
    @State private var token = ""
    @State private var error: String?
    @State private var saving = false
    @State private var confirmingForgetToken = false
    var body: some View {
        @Bindable var fileDisplay = state.fileDisplay
        NavigationStack {
            Form {
                Section(L10n.text("Help & Privacy")) {
                    NavigationLink(L10n.text("Setup guide & support")) { AppDocumentView(document: .support) }.accessibilityIdentifier("supportDocument")
                    NavigationLink(L10n.text("Privacy Policy")) { AppDocumentView(document: .privacy) }.accessibilityIdentifier("privacyDocument")
                    if state.demo {
                        Button(L10n.text("Leave sample library")) { Task { await state.leaveSamples(); dismiss() } }.accessibilityIdentifier("leaveSamples")
                    } else {
                        Button(L10n.text("Try sample library")) {
                            saving = true
                            Task {
                                defer { saving = false }
                                do { try await state.startSamples(); dismiss() } catch { self.error = error.localizedDescription }
                            }
                        }.accessibilityIdentifier("openSamples")
                    }
                }
                Section {
                    Toggle(L10n.text("Hide dotfiles"), isOn: $fileDisplay.hideDotFiles)
                        .accessibilityIdentifier("hideDotFiles")
                } header: { Text(L10n.text("File visibility")) } footer: {
                    Text(L10n.text("Hide files and folders starting with a dot, including .obsidian and its contents. Applies immediately to lists in every repository."))
                }
                if !state.library.repositories.isEmpty {
                    Section(L10n.text("Saved libraries")) {
                        ForEach(state.library.repositories, id: \.storageKey) { saved in
                            Button {
                                Task { await state.selectRepository(saved); dismiss() }
                            } label: {
                                HStack { Text(saved.displayName); Spacer(); if saved.storageKey == state.config.storageKey { Image(systemName: "checkmark") } }
                            }.disabled(state.switchingRepository)
                        }
                        Button(L10n.text("Add library"), systemImage: "plus") { newRepository() }
                    }
                }
                Section(state.addingRepository ? L10n.text("Add repository") : L10n.text("Repository connection")) {
                    Picker(L10n.text("Provider"), selection: $config.provider) {
                        ForEach(RepositoryProvider.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.accessibilityIdentifier("providerPicker")
                    if config.provider == .gitlab { field(L10n.text("GitLab URL"), value: $config.server) }
                    field(config.provider == .gitlab ? L10n.text("Namespace") : L10n.text("Owner"), value: $config.owner)
                    field(L10n.text("Repository"), value: $config.repo)
                    field(L10n.text("Branch"), value: $config.branch)
                }
                Section {
                    SecureField(L10n.text("Paste a read-only token"), text: $token).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive().accessibilityIdentifier("token")
                    if config.provider == .github {
                        Link(L10n.text("Create read-only token"), destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!)
                    } else if let server = config.serverURL {
                        Link(L10n.text("Manage GitLab tokens"), destination: server.appendingPathComponent("-/user_settings/personal_access_tokens"))
                    }
                    if let date = state.tokenEnteredAt { LabeledContent(L10n.text("Added"), value: date.formatted(date: .abbreviated, time: .omitted)) }
                    if let date = state.lastValidatedAt { LabeledContent(L10n.text("Last verified"), value: date.formatted(date: .abbreviated, time: .shortened)) }
                    if !state.demo && state.tokenEnteredAt != nil {
                        Button(L10n.text("Remove local token"), role: .destructive) { confirmingForgetToken = true }
                    }
                } header: { Text(L10n.text("Credentials")) } footer: {
                    Text(config.provider == .github
                         ? L10n.text("Grant access only to the repository you need, with Contents set to Read-only. Tokens stay in the device Keychain and never enter web content. Leave blank to keep the saved token.")
                         : L10n.text("Use GitLab read_api access, preferably a token limited to this project. Namespaces can include group/subgroup. Self-hosted servers require HTTPS. Each project's token stays in Keychain."))
                }
                if let error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("connectionError") } }
                Section {
                    Button {
                        saving = true; error = nil
                        Task {
                            defer { saving = false }
                            do { try await state.connect(config, token: token); token = ""; dismiss() }
                            catch { self.error = error.localizedDescription }
                        }
                    } label: { HStack { Text(L10n.text("Save & verify")); Spacer(); if saving { ProgressView() } } }.disabled(saving || !config.isValid).accessibilityIdentifier("saveConnection")
                }
                Section(L10n.text("Local cache")) {
                    LabeledContent(L10n.text("Storage used"), value: ByteCountFormatter.string(fromByteCount: Int64(state.cacheBytes), countStyle: .file))
                    Picker(L10n.text("Cache limit"), selection: $config.cacheLimitMB) { ForEach([100, 250, 500, 1000], id: \.self) { Text("\($0) MB").tag($0) } }
                    LabeledContent(L10n.text("Text cached"), value: "\(state.prefetchCompleted)/\(state.prefetchTotal)")
                    Button(state.isPrefetching ? L10n.text("Pause caching") : L10n.text("Resume caching")) { if state.isPrefetching { state.stopPrefetch() } else { state.startPrefetch() } }
                    Button(L10n.text("Clear attachment cache")) { Task { await state.clearAttachments() } }
                    Text(L10n.text("Markdown and SVG stay cached. Other attachments are removed by last access time. Text is cached while the app is open for offline search.")).font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    BrandIdentity(markSize: 44).padding(.vertical, 6)
                    LabeledContent(L10n.text("Version"), value: AppDocumentView.version)
                    Text(L10n.text("Read-only · No developer server")).foregroundStyle(.secondary)
                }
                Section(L10n.text("App language")) {
                    Link(L10n.text("Open iOS Settings"), destination: URL(string: UIApplication.openSettingsURLString)!)
                    Text(L10n.text("Change the language in iOS Settings. Your documents keep their original language."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(L10n.text("Settings")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done")) { dismiss() }.disabled(saving).accessibilityIdentifier("closeSettings") }
            }
            .disabled(saving)
            .interactiveDismissDisabled(saving)
            .confirmationDialog(L10n.text("Remove this repository's local token?"), isPresented: $confirmingForgetToken, titleVisibility: .visible) {
                Button(L10n.text("Remove token"), role: .destructive) {
                    do { try state.forgetCredential(); token = "" } catch { self.error = error.localizedDescription }
                }
            } message: { Text(L10n.text("Stops online sync but keeps cached files and reading progress. To revoke access completely, also revoke the token on GitHub or GitLab.")) }
            .onChange(of: config.identity) { _, _ in token = "" }
            .onAppear { if state.addingRepository { newRepository() } else { config = state.config }; Task { await state.updateUsage() } }
        }
    }
    private func newRepository() {
        config = RepositoryConfig(); config.provider = state.config.provider; config.server = state.config.server
        config.owner = state.config.owner; config.repo = ""
        token = ""; error = nil; state.addingRepository = true
    }
    private func field(_ label: String, value: Binding<String>) -> some View {
        HStack {
            Text(label).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            TextField(label, text: value).textInputAutocapitalization(.never).autocorrectionDisabled()
                .multilineTextAlignment(.trailing).environment(\.layoutDirection, .leftToRight)
                .frame(maxWidth: .infinity).accessibilityIdentifier(label)
        }
    }
}
