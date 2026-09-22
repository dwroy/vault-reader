import SwiftUI
import VaultCore

struct RecentView: View {
    let state: AppState
    private func group(_ commit: CommitSummary) -> Int {
        guard let date = commit.date else { return 2 }
        if Calendar.current.isDateInToday(date) { return 0 }
        return Calendar.current.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) ? 1 : 2
    }
    var body: some View {
        List {
            if state.loadingRecent { ProgressView("读取最近提交…") }
            if let error = state.recentError { Text(error).foregroundStyle(.secondary); Button("重试") { Task { await state.loadRecent() } } }
            ForEach(0..<3) { bucket in
                let commits = state.recent.filter { group($0) == bucket }
                if !commits.isEmpty {
                    Section(["今天", "本周", "更早"][bucket]) {
                        ForEach(commits) { commit in CommitRow(state: state, commit: commit) }
                    }
                }
            }
            if state.recent.isEmpty && !state.loadingRecent {
                Text("暂无提交缓存。连接后显示最近 30 条提交。").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("最近")
        .task { await state.loadRecent() }
        .refreshable { await state.refresh(); await state.loadRecent() }
        .safeAreaInset(edge: .top, spacing: 0) { StatusBanner(state: state) }
    }
}
private struct CommitRow: View {
    let state: AppState
    let commit: CommitSummary
    @State private var expanded = false
    @State private var details: CommitFiles?
    @State private var error: String?
    @State private var retry = 0
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Text(commit.commit.message).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
            if let details {
                ForEach(details.files.filter { state.fileDisplay.includes($0.filename) }) { file in
                    if file.status != "removed", state.index.files[file.filename] != nil {
                        NavigationLink(value: ReaderRoute.file(file.filename)) { fileLabel(file) }
                    } else { fileLabel(file).foregroundStyle(.secondary) }
                }
                if !details.files.isEmpty && details.files.allSatisfy({ !state.fileDisplay.includes($0.filename) }) {
                    Text("此提交中的文件已按显示设置隐藏。").font(.caption).foregroundStyle(.secondary)
                }
                Text("文件打开当前分支版本；已删除或不在当前目录树中的文件不可打开。").font(.caption).foregroundStyle(.secondary)
                if details.truncated || details.limitsMayApply == true {
                    Text("服务端可能限制变更清单或内容；完整变更以仓库网页为准。").font(.caption).foregroundStyle(.secondary)
                    Link("在 \(state.config.provider.title) 查看提交", destination: state.config.commitURL(sha: commit.sha))
                }
            } else if let error { Text(error).font(.caption); Button("重试文件列表") { retry += 1 } }
            else { ProgressView("读取文件列表…") }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(commit.title).lineLimit(2)
                if let date = commit.date { Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
            }.padding(.vertical, 3)
        }
        .task(id: "\(expanded)|\(retry)") {
            guard expanded, details == nil else { return }; error = nil
            do { let result = try await state.changedFiles(commit.sha); try Task.checkCancellation(); details = result }
            catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
    private func fileLabel(_ file: ChangedFile) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(file.filename).font(.callout)
            Text(file.status + (file.previous_filename.map { " · 原路径：" + $0 } ?? "")).font(.caption).foregroundStyle(.secondary)
        }
    }
}
