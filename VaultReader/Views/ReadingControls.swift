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
                Button(L10n.text("Contents"), systemImage: "list.bullet") { showingContents = true }.disabled(book.outline.isEmpty).frame(minHeight: 44).accessibilityIdentifier("readingContents")
                Spacer()
                Text("\(book.percent)%").font(.caption.monospacedDigit()).foregroundStyle(.secondary).accessibilityIdentifier("readingProgress")
                Spacer()
                Button(L10n.text("Rendering"), systemImage: "textformat.size") { showingAppearance = true }.frame(minHeight: 44).accessibilityIdentifier("readingAppearance")
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
                .navigationTitle(L10n.text("Contents")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done")) { showingContents = false } } }
            }
        }
        .sheet(isPresented: $showingAppearance) {
            NavigationStack {
                Form {
                    Section(L10n.text("Text size")) {
                        HStack {
                            Button(L10n.text("Smaller"), systemImage: "textformat.size.smaller") { book.record.fontScale = max(0.8, book.record.fontScale - 0.1) }.disabled(book.record.fontScale <= 0.8)
                            Spacer(); Text("\(Int((book.record.fontScale * 100).rounded()))%").monospacedDigit(); Spacer()
                            Button(L10n.text("Larger"), systemImage: "textformat.size.larger") { book.record.fontScale = min(1.6, book.record.fontScale + 0.1) }.disabled(book.record.fontScale >= 1.6)
                        }.buttonStyle(.bordered)
                    }
                    Section(L10n.text("Appearance")) {
                        Picker(L10n.text("Theme"), selection: $book.record.theme) {
                            Text(L10n.text("System")).tag(ReadingTheme.system)
                            Text(L10n.text("Light")).tag(ReadingTheme.light)
                            Text(L10n.text("Sepia")).tag(ReadingTheme.sepia)
                            Text(L10n.text("Dark")).tag(ReadingTheme.dark)
                        }.pickerStyle(.inline)
                    }
                    Text(L10n.text("Your reading position is saved automatically on this device.")).font(.caption).foregroundStyle(.secondary)
                }
                .navigationTitle(L10n.text("Reading appearance")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done")) { showingAppearance = false } } }
            }.presentationDetents([.medium, .large])
        }
        .onChange(of: book.record.fontScale) { book.preferencesChanged() }
        .onChange(of: book.record.theme) { book.preferencesChanged() }
    }
}
