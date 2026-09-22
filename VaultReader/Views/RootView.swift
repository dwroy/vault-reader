import SwiftUI

struct NoteRoute: Hashable { let path: String; var anchor = "" }
enum ReaderRoute: Hashable { case note(NoteRoute), directory(String), file(String) }
private enum ReaderTab: Hashable { case directory, recent, search, settings }
struct RootView: View {
    @Bindable var state: AppState
    @State private var selectedTab: ReaderTab = .directory
    @State private var recentPath: [ReaderRoute] = []
    @State private var searchPath: [ReaderRoute] = []
    @State private var directoryPath: [ReaderRoute] = []
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if !state.ready { ProgressView("打开知识库…") }
            else if state.needsSetup && state.index.entries.isEmpty {
                WelcomeView(state: state)
            } else {
                TabView(selection: $selectedTab) {
                    NavigationStack(path: $directoryPath) {
                        DirView(state: state, path: "")
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
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
                    NavigationStack(path: $recentPath) {
                        RecentView(state: state)
                            .navigationDestination(for: ReaderRoute.self) { route in destination(route, path: $recentPath) }
                    }.tabItem { Label("最近", systemImage: "clock") }.tag(ReaderTab.recent)
                    NavigationStack(path: $searchPath) {
                        SearchView(state: state)
                            .navigationDestination(for: ReaderRoute.self) { route in destination(route, path: $searchPath) }
                    }.tabItem { Label("搜索", systemImage: "magnifyingglass") }.tag(ReaderTab.search)
                    SettingsView(state: state, isTab: true) { selectedTab = .directory }
                        .tabItem { Label("设置", systemImage: "gearshape") }.tag(ReaderTab.settings)
                }.id(state.config.identity + "#" + state.config.branch)

            }
        }
        .tint(Color(red: 0.14, green: 0.46, blue: 0.35))
        .sheet(isPresented: $state.showSettings) { SettingsView(state: state) }
        .task { await state.start(); if !state.needsSetup { state.startPrefetch() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active && state.ready { if !state.needsSetup { state.startPrefetch() }; Task { await state.refresh() } } else if phase == .background { state.stopPrefetch() } }
        .onChange(of: state.config) { _, _ in directoryPath = []; recentPath = []; searchPath = []; selectedTab = .directory }
    }
    @ViewBuilder private func destination(_ route: ReaderRoute, path: Binding<[ReaderRoute]>) -> some View {
        switch route {
        case .note(let note): NoteView(state: state, route: note, navigate: { path.wrappedValue.append($0) })
        case .file(let file):
            if state.index.files[file]?.isMarkdown == true {
                NoteView(state: state, route: NoteRoute(path: file), navigate: { path.wrappedValue.append($0) })
            } else if state.index.files[file]?.isHTML == true {
                HTMLReaderView(state: state, path: file, navigate: { path.wrappedValue.append(.file($0)) })
            } else { AttachmentView(state: state, path: file) }
        case .directory(let directory): DirView(state: state, path: directory)
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
                Text("让笔记，\n随身可读。").font(.system(size: 38, weight: .semibold, design: .serif)).lineSpacing(6)
                Text("连接你的 GitHub 或 GitLab 知识库。\n从目录出发，沿着双链慢慢读。").font(.body).foregroundStyle(.secondary).lineSpacing(6)
                if let error = state.error { Text(error).font(.callout).foregroundStyle(.red) }
                Button { state.showSettings = true } label: { Label("连接知识库", systemImage: "arrow.right").frame(maxWidth: .infinity).padding(.vertical, 8) }.buttonStyle(.borderedProminent)
                Text("只读访问 · Token 保存在设备钥匙串").font(.caption).foregroundStyle(.secondary)
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
