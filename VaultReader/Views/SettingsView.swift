import VaultCore
import SwiftUI

struct SettingsView: View {
    let state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var config = RepositoryConfig()
    @State private var token = ""
    @State private var error: String?
    @State private var saving = false
    var body: some View {
        NavigationStack {
            Form {
                Section("GitHub 仓库") {
                    field("Owner", value: $config.owner)
                    field("Repository", value: $config.repo)
                    field("分支", value: $config.branch)
                    field("首页", value: $config.home)
                }
                Section {
                    SecureField("粘贴 fine-grained Token", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive().accessibilityIdentifier("token")
                    Link("创建只读 Token", destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!)
                    if let date = state.tokenEnteredAt { LabeledContent("录入日期", value: date.formatted(date: .abbreviated, time: .omitted)) }
                    if let date = state.lastValidatedAt { LabeledContent("上次校验", value: date.formatted(date: .abbreviated, time: .shortened)) }
                } header: { Text("安全凭据") } footer: {
                    Text("只授权这一个仓库，Contents 选择 Read-only。Token 仅存于本机 Keychain，不会交给网页。留空可沿用已保存的凭据。")
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
                    Button("清理附件缓存") { Task { await state.clearAttachments() } }
                    Text("Markdown 与 SVG 保留，其他附件按最近访问时间淘汰。当前只缓存打开过的内容。").font(.caption).foregroundStyle(.secondary)
                }
                Section { LabeledContent("版本", value: "0.1.0 · M1a"); Text("只读 · 无服务器").foregroundStyle(.secondary) }
            }
            .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.disabled(saving) } }
            .disabled(saving)
            .interactiveDismissDisabled(saving)
            .onAppear { config = state.config; Task { await state.updateUsage() } }
        }
    }
    private func field(_ label: String, value: Binding<String>) -> some View {
        HStack { Text(label).frame(width: 92, alignment: .leading); TextField(label, text: value).textInputAutocapitalization(.never).autocorrectionDisabled().multilineTextAlignment(.trailing).accessibilityIdentifier(label) }
    }
}
