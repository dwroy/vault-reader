import SwiftUI
import VaultCore

struct ReadingControls: View {
    @Bindable var book: BookSession
    @State private var showingContents = false
    @State private var showingAppearance = false
    var body: some View {
        VStack(spacing: 4) {
            if let error = book.store.saveError { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button("目录", systemImage: "list.bullet") { showingContents = true }.disabled(book.outline.isEmpty).frame(minHeight: 44).accessibilityIdentifier("readingContents")
                Spacer()
                Text("\(book.percent)%").font(.caption.monospacedDigit()).foregroundStyle(.secondary).accessibilityIdentifier("readingProgress")
                Spacer()
                Button("排版", systemImage: "textformat.size") { showingAppearance = true }.frame(minHeight: 44).accessibilityIdentifier("readingAppearance")
            }.font(.subheadline).padding(.horizontal, 20).padding(.vertical, 6)
        }
        .background(.bar).tint(.primary)
        .sheet(isPresented: $showingContents) {
            NavigationStack {
                List(book.outline) { item in
                    Button {
                        book.viewport.go(to: item.id); showingContents = false
                    } label: { Text(item.title).padding(.leading, CGFloat(max(0, item.level - 1)) * 12).foregroundStyle(.primary) }
                }
                .navigationTitle("章节目录").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingContents = false } } }
            }
        }
        .sheet(isPresented: $showingAppearance) {
            NavigationStack {
                Form {
                    Section("字号") {
                        HStack {
                            Button("缩小", systemImage: "textformat.size.smaller") { book.record.fontScale = max(0.8, book.record.fontScale - 0.1) }.disabled(book.record.fontScale <= 0.8)
                            Spacer(); Text("\(Int((book.record.fontScale * 100).rounded()))%").monospacedDigit(); Spacer()
                            Button("放大", systemImage: "textformat.size.larger") { book.record.fontScale = min(1.6, book.record.fontScale + 0.1) }.disabled(book.record.fontScale >= 1.6)
                        }.buttonStyle(.bordered)
                    }
                    Section("纸张") {
                        Picker("主题", selection: $book.record.theme) {
                            Text("跟随系统").tag(ReadingTheme.system)
                            Text("浅色").tag(ReadingTheme.light)
                            Text("护眼纸").tag(ReadingTheme.sepia)
                            Text("深色").tag(ReadingTheme.dark)
                        }.pickerStyle(.inline)
                    }
                    Text("阅读位置会自动保存在这台设备上。").font(.caption).foregroundStyle(.secondary)
                }
                .navigationTitle("阅读排版").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingAppearance = false } } }
            }.presentationDetents([.medium, .large])
        }
        .onChange(of: book.record.fontScale) { book.preferencesChanged() }
        .onChange(of: book.record.theme) { book.preferencesChanged() }
    }
}
