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
            if state.loadingRecent { ProgressView(L10n.text("Loading recent commits…")) }
            if let error = state.recentError { Text(error).foregroundStyle(.secondary); Button(L10n.text("Retry")) { Task { await state.loadRecent() } } }
            ForEach(0..<3) { bucket in
                let commits = state.recent.filter { group($0) == bucket }
                if !commits.isEmpty {
                    Section([L10n.text("Today"), L10n.text("This week"), L10n.text("Earlier")][bucket]) {
                        ForEach(commits) { commit in CommitRow(state: state, commit: commit) }
                    }
                }
            }
            if state.recent.isEmpty && !state.loadingRecent {
                Text(L10n.text("No cached commits. Connect to load the 30 most recent commits.")).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(L10n.text("Recent"))
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
                    Text(L10n.text("Files in this commit are hidden by your visibility settings.")).font(.caption).foregroundStyle(.secondary)
                }
                Text(L10n.text("Files open from the current branch. Deleted files and files outside the current tree cannot be opened.")).font(.caption).foregroundStyle(.secondary)
                if details.truncated || details.limitsMayApply == true {
                    Text(L10n.text("The service may limit this change list. Open the repository website for the full changes.")).font(.caption).foregroundStyle(.secondary)
                    Link(L10n.format("View commit on %1$@", state.config.provider.title), destination: state.config.commitURL(sha: commit.sha))
                }
            } else if let error { Text(error).font(.caption); Button(L10n.text("Retry file list")) { retry += 1 } }
            else { ProgressView(L10n.text("Loading file list…")) }
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
            Text(file.status + (file.previous_filename.map { L10n.text(" · Previous path: ") + $0 } ?? "")).font(.caption).foregroundStyle(.secondary)
        }
    }
}
