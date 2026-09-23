import SwiftUI
import VaultCore

struct NoteRoute: Hashable { let path: String; var anchor = ""; var reading = false }
enum ReaderRoute: Hashable { case note(NoteRoute), directory(String), file(String), readingLibrary, book(ListedBook) }
private enum ReaderTab: Hashable { case directory, reading, recent, search }
struct RootView: View {
    @Bindable var state: AppState
    @State private var selectedTab: ReaderTab = .directory
    @State private var readingPath: [ReaderRoute] = []
    @State private var readingProject: String?
    @State private var recentPath: [ReaderRoute] = []
    @State private var searchPath: [ReaderRoute] = []
    @State private var directoryPath: [ReaderRoute] = []
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if !state.ready { ProgressView("打开知识库…") }
            else if state.needsSetup && state.index.entries.isEmpty && state.library.repositories.isEmpty {
                WelcomeView(state: state)
            } else {
                TabView(selection: $selectedTab) {
                    NavigationStack(path: $directoryPath) {
                        DirView(state: state, path: "")
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) {
                                    Menu {
                                        ForEach(state.library.repositories, id: \.storageKey) { saved in
                                            Button { Task { await state.selectRepository(saved) } } label: {
                                                if saved.storageKey == state.config.storageKey { Label(saved.displayName, systemImage: "checkmark") }
                                                else { Text(saved.displayName) }
                                            }
                                        }
                                        Divider()
                                        Button("添加知识库", systemImage: "plus") { state.addingRepository = true; state.showSettings = true }
                                    } label: { BrandMark(size: 28) }.accessibilityLabel("切换知识库")
                                }
                            }
                            .navigationDestination(for: ReaderRoute.self) { route in destination(route, path: $directoryPath) }
                    }.tabItem { Label("目录", systemImage: "folder") }.tag(ReaderTab.directory)
                    NavigationStack(path: $readingPath) {
                        ReadingProjectsView(state: state) { config, resumePath in
                            readingProject = config.storageKey
                            Task {
                                await state.selectRepository(config)
                                guard state.config.storageKey == config.storageKey else { readingProject = nil; return }
                                selectedTab = .reading
                                readingPath = [.readingLibrary]
                                if let resumePath { readingPath.append(readingRoute(resumePath, index: state.index)) }
                                readingProject = nil
                            }
                        }
                        .navigationDestination(for: ReaderRoute.self) { route in destination(route, path: $readingPath) }
                    }.tabItem { Label("阅读", systemImage: "book") }.tag(ReaderTab.reading)
                    NavigationStack(path: $recentPath) {
                        RecentView(state: state)
                            .navigationDestination(for: ReaderRoute.self) { route in destination(route, path: $recentPath) }
                    }.tabItem { Label("最近", systemImage: "clock") }.tag(ReaderTab.recent)
                    NavigationStack(path: $searchPath) {
                        SearchView(state: state)
                            .navigationDestination(for: ReaderRoute.self) { route in destination(route, path: $searchPath) }
                    }.tabItem { Label("搜索", systemImage: "magnifyingglass") }.tag(ReaderTab.search)
                }.id(state.config.identity + "#" + state.config.branch)

            }
        }
        .tint(Color(red: 0.11, green: 0.37, blue: 0.29))
        .sheet(isPresented: $state.showSettings) { SettingsView(state: state) }
        .task {
            await state.start(); if !state.needsSetup { state.startPrefetch() }
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if let flag = args.firstIndex(of: "--read-file"), args.indices.contains(flag + 1), state.index.files[args[flag + 1]] != nil {
                selectedTab = .reading
                readingPath = [.readingLibrary, readingRoute(args[flag + 1], index: state.index)]
            }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active && state.ready { if !state.needsSetup { state.startPrefetch() }; Task { await state.refresh() } } else if phase == .background { state.stopPrefetch(); state.reading.flush() } }
        .onChange(of: state.config) { _, _ in directoryPath = []; recentPath = []; searchPath = []; readingPath = []; selectedTab = readingProject == state.config.storageKey ? .reading : .directory }
    }
    @ViewBuilder private func destination(_ route: ReaderRoute, path: Binding<[ReaderRoute]>) -> some View {
        switch route {
        case .note(let note): NoteView(state: state, route: note, navigate: { path.wrappedValue.append($0) }, readingBook: note.reading || BookCatalog.root(for: note.path) != nil)
        case .file(let file):
            if state.index.files[file]?.isMarkdown == true {
                NoteView(state: state, route: NoteRoute(path: file), navigate: { path.wrappedValue.append($0) }, readingBook: BookCatalog.root(for: file) != nil)
            } else if state.index.files[file]?.isHTML == true {
                HTMLReaderView(state: state, path: file, navigate: { path.wrappedValue.append(.file($0)) })
            } else if state.index.files[file]?.ext == "pdf" { PDFReaderView(state: state, path: file) }
            else { AttachmentView(state: state, path: file) }
        case .directory(let directory): DirView(state: state, path: directory)
        case .readingLibrary: ReadingLibraryView(state: state)
        case .book(let book): BookDetailView(state: state, book: book)
        }
    }

}

struct WelcomeView: View {
    @Bindable var state: AppState
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Spacer()
                BrandIdentity(markSize: 68)
                Text("Agent 整理，\n随手开读。").font(.system(size: 38, weight: .semibold, design: .serif)).lineSpacing(6)
                Text("用 Claude、Codex 等工具维护知识，\n在手机上随时阅读。").font(.body).foregroundStyle(.secondary).lineSpacing(6)
                if let error = state.error { Text(error).font(.callout).foregroundStyle(.red) }
                Button { state.showSettings = true } label: { Label("连接知识库", systemImage: "arrow.right").frame(maxWidth: .infinity).padding(.vertical, 8) }.buttonStyle(.borderedProminent)
                Text("原生支持 Git · Markdown · HTML\nGitHub / GitLab 只读访问 · Token 保存在设备钥匙串").font(.caption).foregroundStyle(.secondary).lineSpacing(4)
                Spacer(); Spacer()
            }.padding(30).navigationTitle("Vault Reader").navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct StatusBanner: View {
    let state: AppState
    var body: some View {
        if let notice = state.notice {
            HStack(spacing: 7) {
                if state.isRefreshing { ProgressView().controlSize(.mini) }
                else { Image(systemName: state.isOffline ? "wifi.slash" : "checkmark.circle") }
                Text(state.isOffline ? "离线 · " + notice : notice).font(.caption)
                Spacer(minLength: 0)
            }.foregroundStyle(state.isOffline ? Color.orange : Color.secondary)
                .padding(.horizontal, 18).padding(.vertical, 7).background(.bar)
        }
    }
}
