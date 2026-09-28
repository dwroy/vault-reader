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
                Section("帮助与隐私") {
                    NavigationLink("连接指南与支持") { AppDocumentView(document: .support) }.accessibilityIdentifier("supportDocument")
                    NavigationLink("隐私政策") { AppDocumentView(document: .privacy) }.accessibilityIdentifier("privacyDocument")
                    if state.demo {
                        Button("退出示例知识库") { Task { await state.leaveSamples(); dismiss() } }.accessibilityIdentifier("leaveSamples")
                    } else {
                        Button("体验示例知识库") {
                            saving = true
                            Task {
                                defer { saving = false }
                                do { try await state.startSamples(); dismiss() } catch { self.error = error.localizedDescription }
                            }
                        }.accessibilityIdentifier("openSamples")
                    }
                }
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
                                Task { await state.selectRepository(saved); dismiss() }
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
                    if !state.demo && state.tokenEnteredAt != nil {
                        Button("移除本机 Token", role: .destructive) { confirmingForgetToken = true }
                    }
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
                            do { try await state.connect(config, token: token); token = ""; dismiss() }
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
                    LabeledContent("版本", value: AppDocumentView.version)
                    Text("只读 · 无服务器").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.disabled(saving) }
            }
            .disabled(saving)
            .interactiveDismissDisabled(saving)
            .confirmationDialog("移除这个知识库的本机 Token？", isPresented: $confirmingForgetToken, titleVisibility: .visible) {
                Button("移除 Token", role: .destructive) {
                    do { try state.forgetCredential(); token = "" } catch { self.error = error.localizedDescription }
                }
            } message: { Text("停止联网同步，保留本机缓存和阅读进度。要彻底撤销访问，请同时在 GitHub 或 GitLab 中撤销 Token。") }
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
        HStack { Text(label).frame(width: 92, alignment: .leading); TextField(label, text: value).textInputAutocapitalization(.never).autocorrectionDisabled().multilineTextAlignment(.trailing).accessibilityIdentifier(label) }
    }
}
