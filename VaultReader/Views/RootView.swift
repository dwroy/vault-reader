import SwiftUI

struct NoteRoute: Hashable { let path: String; var anchor = "" }
enum ReaderRoute: Hashable { case note(NoteRoute), directory(String) }
struct RootView: View {
    @Bindable var state: AppState
    @State private var homePath: [ReaderRoute] = []
    @State private var directoryPath: [ReaderRoute] = []
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if !state.ready { ProgressView("打开知识库…") }
            else if state.needsSetup && state.index.entries.isEmpty {
                WelcomeView(state: state)
            } else {
                TabView {
                    NavigationStack(path: $homePath) {
                        NoteView(state: state, route: NoteRoute(path: state.config.home), navigate: { homePath.append(.note($0)) })
                            .navigationTitle("知识库")
                            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("设置", systemImage: "gearshape") { state.showSettings = true }.labelStyle(.iconOnly) } }
                            .navigationDestination(for: ReaderRoute.self) { route in destination(route, path: $homePath) }
                    }.tabItem { Label("首页", systemImage: "book.closed") }
                    NavigationStack(path: $directoryPath) {
                        DirView(state: state, path: "")
                            .navigationDestination(for: ReaderRoute.self) { route in destination(route, path: $directoryPath) }
                    }.tabItem { Label("目录", systemImage: "folder") }
                }.id(state.config.identity + "#" + state.config.branch)

            }
        }
        .tint(Color(red: 0.14, green: 0.46, blue: 0.35))
        .sheet(isPresented: $state.showSettings) { SettingsView(state: state) }
        .task { await state.start() }
        .onChange(of: scenePhase) { _, phase in if phase == .active && state.ready { Task { await state.refresh() } } }
        .onChange(of: state.config) { _, _ in homePath = []; directoryPath = [] }
    }
    @ViewBuilder private func destination(_ route: ReaderRoute, path: Binding<[ReaderRoute]>) -> some View {
        switch route {
        case .note(let note): NoteView(state: state, route: note, navigate: { path.wrappedValue.append(.note($0)) })
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
                Image(systemName: "books.vertical").font(.system(size: 48, weight: .light)).foregroundStyle(.tint)
                Text("让笔记，\n随身可读。").font(.system(size: 38, weight: .semibold, design: .serif)).lineSpacing(6)
                Text("连接你的 GitHub 知识库。\n从首页出发，沿着双链慢慢读。").font(.body).foregroundStyle(.secondary).lineSpacing(6)
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
                Text(notice).font(.caption)
                Spacer(minLength: 0)
            }.foregroundStyle(state.isOffline ? Color.orange : Color.secondary)
                .padding(.horizontal, 18).padding(.vertical, 7).background(.bar)
        }
    }
}
