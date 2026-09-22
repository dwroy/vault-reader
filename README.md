# Vault Reader

A native, read-only reader for an Obsidian vault stored in GitHub or GitLab. **iOS first, Android next.** No server or account system; a repository-scoped, read-only token stays in the device credential store.

M1b implementation candidate: saved repositories with quick switching (GitHub, GitLab.com and HTTPS self-managed GitLab), Directory first, Recent commits, local filename/full-text Search, Directory, Markdown completion, independent HTML readers, images/QuickLook and content-addressed cache. A personal-team build has been installed and exercised on iPhone. Private-repository online sync and the remaining device acceptance limits are recorded in docs/ACCEPTANCE.md. Android is architecturally prepared, not yet implemented.

## Architecture

- `packages/reader-web`: shared JavaScript Markdown/Obsidian renderer, link resolver and CSS. Runs unchanged in WKWebView or a future Android WebView host.
- `packages/contracts`: versioned reader/native bridge types. No token or native filesystem paths enter the renderer.
- `packages/VaultCore`: Swift package with GitHub transport, tree index and disk cache. Apple implementation; Android will implement equivalent native adapters in Kotlin.
- `VaultReader`: iOS SwiftUI shell, Keychain, WKWebView, navigation and QuickLook.

See [architecture and Android integration plan](docs/ARCHITECTURE.md) and [acceptance status](docs/ACCEPTANCE.md).

## Build

Requires Xcode 26.3, XcodeGen and an iOS 18+ target. The renderer bundle is committed, so a normal Xcode build does not need Node or network access.

```sh
xcodegen generate
xcodebuild -scheme VaultReader -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/DerivedData build
```

After changing renderer source:

```sh
npm ci
npm run build:renderer
```

Simulator tests use Xcode's default ad-hoc signing. Do not disable code signing: real Keychain calls require the generated entitlements even in a simulator.

The build script also accepts an output directory: `node scripts/build-renderer.mjs <directory>`. Android can package the same generated folder as app assets when implementation starts.

For device builds, select your **personal** developer team in Xcode's Signing & Capabilities; no team ID is committed. Bundle ID: `com.dwroy.vaultreader`.

## Connect

Use Directory’s **Switch vault** menu or Settings → **Add vault** to save multiple connections. GitHub uses a fine-grained token with **Contents: Read-only**. GitLab uses **read_api**; prefer a project-scoped access token when available. Select the platform, enter the GitLab base HTTPS address if applicable, owner or group/subgroup, repository and branch, then paste the corresponding token. Blank token input preserves an existing credential; the app validates the proposed repository before switching. Tokens are never stored in UserDefaults, logs or web content. Profiles and last selection persist; tokens, blobs, metadata, HTML origins and search data stay isolated by service/repository. Changing the platform or repository clears any unsaved token draft.

Debug builds optionally accept `VR_TOKEN` on first launch. Use Xcode's launch environment or an existing secure local environment; never put a token in scripts, launch arguments, screenshots, source or commits. Release builds do not contain this injection path.

## Verify

```sh
npm test
swift test --package-path packages/VaultCore
xcodebuild -scheme VaultReader -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/DerivedData test
node tests/resolve-links.mjs /path/to/vault --summary
```

Remove `--summary` for unresolved/ambiguous links. Reports contain private filenames: keep them in ignored `build/`, never commit them. Only git-tracked files are scanned.

Debug launch argument `--demo` uses synthetic sample notes, commit records and HTML readers in a separate repository cache namespace. For offline acceptance with a local vault, install the app in a booted simulator, run `python3 scripts/seed-simulator.py /path/to/vault <simulator-udid>`, then launch with `--cached-vault`. This imports only git HEAD Markdown and small images into that simulator's app cache, never the code repository. It is an offline fixture, not a GitHub connectivity test.

## License

MIT. Vendored dependency license notices ship in `VaultReader/Resources/renderer/vendor/THIRD-PARTY-NOTICES.txt`.
