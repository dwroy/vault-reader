import VaultCore
import SwiftUI

struct SettingsView: View {
    let state: AppState
    var isTab = false
    var didConnect: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var config = RepositoryConfig()
    @State private var token = ""
    @State private var error: String?
    @State private var saving = false
    var body: some View {
        @Bindable var fileDisplay = state.fileDisplay
        NavigationStack {
            Form {
                Section {
                    Toggle("隐藏以点开头的文件", isOn: $fileDisplay.hideDotFiles)
                        .accessibilityIdentifier("hideDotFiles")
                } header: { Text("文件显示") } footer: {
                    Text("同时隐藏 .obsidian 等以点开头的文件夹及其内容。适用于所有仓库的目录、阅读、搜索和最近文件列表，修改立即生效。")
                }
                if !state.library.repositories.isEmpty {
                    Section("已保存知识库") {
                        ForEach(state.library.repositories, id: \.storageKey) { saved in
                            Button {
                                Task { await state.selectRepository(saved); finishConnecting() }
                            } label: {
                                HStack { Text(saved.displayName); Spacer(); if saved.storageKey == state.config.storageKey { Image(systemName: "checkmark") } }
                            }.disabled(state.switchingRepository)
                        }
                        Button("添加知识库", systemImage: "plus") { newRepository() }
                    }
                }
                Section(state.addingRepository ? "添加仓库" : "仓库连接") {
                    Picker("平台", selection: $config.provider) {
                        ForEach(RepositoryProvider.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.accessibilityIdentifier("providerPicker")
                    if config.provider == .gitlab { field("GitLab 地址", value: $config.server) }
                    field(config.provider == .gitlab ? "命名空间" : "Owner", value: $config.owner)
                    field("Repository", value: $config.repo)
                    field("分支", value: $config.branch)
                }
                Section {
                    SecureField("粘贴只读 Token", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive().accessibilityIdentifier("token")
                    if config.provider == .github {
                        Link("创建只读 Token", destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!)
                    } else if let server = config.serverURL {
                        Link("管理 GitLab Token", destination: server.appendingPathComponent("-/user_settings/personal_access_tokens"))
                    }
                    if let date = state.tokenEnteredAt { LabeledContent("录入日期", value: date.formatted(date: .abbreviated, time: .omitted)) }
                    if let date = state.lastValidatedAt { LabeledContent("上次校验", value: date.formatted(date: .abbreviated, time: .shortened)) }
                } header: { Text("安全凭据") } footer: {
                    Text(config.provider == .github
                         ? "只授权对应仓库，Contents 选择 Read-only。每个仓库的 Token 分别保存在本机 Keychain，不会交给网页。留空沿用该仓库已有凭据。"
                         : "GitLab 使用 read_api 只读权限；如可用，优先使用仅授权此项目的 Access Token。命名空间可含多级 group/subgroup。自建地址需使用 HTTPS。凭据按服务与项目独立保存在 Keychain。")
                }
                if let error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("connectionError") } }
                Section {
                    Button {
                        saving = true; error = nil
                        Task {
                            defer { saving = false }
                            do { try await state.connect(config, token: token); token = ""; finishConnecting() }
                            catch { self.error = error.localizedDescription }
                        }
                    } label: { HStack { Text("保存并校验"); Spacer(); if saving { ProgressView() } } }.disabled(saving || !config.isValid).accessibilityIdentifier("saveConnection")
                }
                Section("本机缓存") {
                    LabeledContent("文件占用", value: ByteCountFormatter.string(fromByteCount: Int64(state.cacheBytes), countStyle: .file))
                    Picker("缓存上限", selection: $config.cacheLimitMB) { ForEach([100, 250, 500, 1000], id: \.self) { Text("\($0) MB").tag($0) } }
                    LabeledContent("正文补全", value: "\(state.prefetchCompleted)/\(state.prefetchTotal)")
                    Button(state.isPrefetching ? "暂停补全" : "继续补全") { if state.isPrefetching { state.stopPrefetch() } else { state.startPrefetch() } }
                    Button("清理附件缓存") { Task { await state.clearAttachments() } }
                    Text("Markdown 与 SVG 保留，其他附件按最近访问时间淘汰。Markdown 在前台自动补全，可离线搜索正文。").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    BrandIdentity(markSize: 44).padding(.vertical, 6)
                    LabeledContent("版本", value: "0.2.0 · M1b")
                    Text("只读 · 无服务器").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isTab { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.disabled(saving) } }
            }
            .disabled(saving)
            .interactiveDismissDisabled(saving)
            .onChange(of: config.identity) { _, _ in token = "" }
            .onAppear { if state.addingRepository { newRepository() } else { config = state.config }; Task { await state.updateUsage() } }
        }
    }
    private func finishConnecting() {
        if isTab { didConnect?() } else { dismiss() }
    }
    private func newRepository() {
        config = RepositoryConfig(); config.provider = state.config.provider; config.server = state.config.server
        config.owner = state.config.owner; config.repo = ""
        token = ""; error = nil; state.addingRepository = true
    }
    private func field(_ label: String, value: Binding<String>) -> some View {
        HStack { Text(label).frame(width: 92, alignment: .leading); TextField(label, text: value).textInputAutocapitalization(.never).autocorrectionDisabled().multilineTextAlignment(.trailing).accessibilityIdentifier(label) }
    }
}
