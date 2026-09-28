import SwiftUI
import VaultCore

struct NoteRoute: Hashable { let path: String; var anchor = ""; var reading = false; var searchTerms: [String] = [] }
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
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        Group {
            if !state.ready { ProgressView(L10n.text("Opening library…")) }
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
                                        Button(L10n.text("Add library"), systemImage: "plus") { state.addingRepository = true; state.showSettings = true }
                                    } label: { BrandMark(size: 28) }.accessibilityLabel(L10n.text("Switch library"))
                                }
                            }
                            .navigationDestination(for: ReaderRoute.self) { route in destination(route, path: $directoryPath) }
                    }.tabItem { Label(L10n.text("Files"), systemImage: "folder") }.tag(ReaderTab.directory)
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
                    }.tabItem { Label(L10n.text("Reading"), systemImage: "book") }.tag(ReaderTab.reading)
                    NavigationStack(path: $recentPath) {
                        RecentView(state: state)
                            .navigationDestination(for: ReaderRoute.self) { route in destination(route, path: $recentPath) }
                    }.tabItem { Label(L10n.text("Recent"), systemImage: "clock") }.tag(ReaderTab.recent)
                    NavigationStack(path: $searchPath) {
                        SearchView(state: state)
                            .navigationDestination(for: ReaderRoute.self) { route in destination(route, path: $searchPath) }
                    }.tabItem { Label(L10n.text("Search"), systemImage: "magnifyingglass") }.tag(ReaderTab.search)
                }.id(state.config.identity + "#" + state.config.branch)

            }
        }
        .tint(colorScheme == .dark ? Color(red: 0.55, green: 0.80, blue: 0.68) : Color(red: 0.11, green: 0.37, blue: 0.29))
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
    @State private var openingSamples = false
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Spacer()
                BrandIdentity(markSize: 68)
                Text(L10n.text("AI Native.\nReady to read.")).font(.system(size: 38, weight: .semibold, design: .serif)).lineSpacing(6)
                Text(L10n.text("Organize knowledge with Claude, Codex and other tools. Read it wherever you are.")).font(.body).foregroundStyle(.secondary).lineSpacing(6)
                if let error = state.error { Text(error).font(.callout).foregroundStyle(.red) }
                Button { state.showSettings = true } label: { Label(L10n.text("Connect library"), systemImage: "arrow.forward").frame(maxWidth: .infinity).padding(.vertical, 8).foregroundStyle(colorScheme == .dark ? Color.black : Color.white) }.buttonStyle(.borderedProminent)
                Button {
                    openingSamples = true
                    Task {
                        defer { openingSamples = false }
                        do { try await state.startSamples() } catch { state.error = error.localizedDescription }
                    }
                } label: { Label(L10n.text("Try sample library"), systemImage: "book").frame(maxWidth: .infinity).padding(.vertical, 6) }
                    .buttonStyle(.bordered).disabled(openingSamples).accessibilityIdentifier("openSamples")
                Text(L10n.text("Native Markdown · HTML · PDF\nRead-only GitHub / GitLab access · Tokens stay in Keychain")).font(.caption).foregroundStyle(.secondary).lineSpacing(4)
                HStack {
                    NavigationLink(L10n.text("Help")) { AppDocumentView(document: .support) }
                    Spacer()
                    NavigationLink(L10n.text("Privacy Policy")) { AppDocumentView(document: .privacy) }
                }.font(.footnote)
                Spacer(); Spacer()
            }.frame(maxWidth: 600).frame(maxWidth: .infinity).padding(30).navigationTitle("Vault Reader").navigationBarTitleDisplayMode(.inline)
            }
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
                Text(state.isOffline ? L10n.text("Offline · ") + notice : notice).font(.caption)
                Spacer(minLength: 0)
            }.foregroundStyle(state.isOffline ? Color.orange : Color.secondary)
                .padding(.horizontal, 18).padding(.vertical, 7).background(.bar)
        }
    }
}
