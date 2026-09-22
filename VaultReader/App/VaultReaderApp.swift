import SwiftUI

@main struct VaultReaderApp: App {
    @State private var state = AppState()
    var body: some Scene { WindowGroup { RootView(state: state) } }
}
