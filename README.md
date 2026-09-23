# Vault Reader

**AI 时代的随身知识库 · Agent 整理，随手开读。** 原生支持 Git · Markdown · HTML.

A native, read-only reader for plain-text knowledge bases: a GitHub or GitLab repository of Markdown, HTML and supporting files, written and reorganized by agents such as Claude Code and Codex. Agents keep working through files and commits; the app only reads, so it never competes with them for writes. Existing Obsidian vaults work as-is, including wikilinks and embeds. **iOS first, Android next.** No server or account system; a repository-scoped, read-only token stays in the device credential store. Store-ready copy lives in [docs/APP-DESCRIPTION.md](docs/APP-DESCRIPTION.md).

M1b implementation candidate: saved repositories with quick switching (GitHub, GitLab.com and HTTPS self-managed GitLab), Directory first, a project-based Reading tab, Recent commits, local filename/full-text Search, Settings, Markdown completion, independent HTML readers, images/QuickLook and content-addressed cache. A personal-team build has been installed and exercised on iPhone. Private-repository online sync and the remaining device acceptance limits are recorded in docs/ACCEPTANCE.md. Android is architecturally prepared, not yet implemented.

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

Use Directory’s **Switch vault** menu or Settings → **Add vault** (Directory’s ⋯ menu → **Settings**) to save multiple connections. GitHub uses a fine-grained token with **Contents: Read-only**. GitLab uses **read_api**; prefer a project-scoped access token when available. Select the platform, enter the GitLab base HTTPS address if applicable, owner or group/subgroup, repository and branch, then paste the corresponding token. Blank token input preserves an existing credential; the app validates the proposed repository before switching. Tokens are never stored in UserDefaults, logs or web content. Profiles and last selection persist; tokens, blobs, metadata, HTML origins and search data stay isolated by service/repository. Changing the platform or repository clears any unsaved token draft.

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

## Reading books, papers and articles

The tabs are **Directory → Reading → Recent → Search**; Settings opens from Directory’s ⋯ menu, below Refresh. Reading first lists saved repository/branch projects; selecting one opens its books and articles. Files under `read`, `reading`, `books`, `papers` or `articles` are discovered automatically. Book folders keep original text, summaries, review notes and HTML editions together. Indexed local PDFs linked from top-level reading lists also appear; external links are not imported. Other Markdown files offer **Open in reader** in their action menu.

Markdown reading provides a heading directory, adjustable font size, system/light/sepia/dark paper and automatic position recovery. Position is stored relative to its heading so font changes and many content updates can retain the place. PDFKit remembers the PDF page and supports its existing outline or manual page entry. HTML retains its own chapter/theme state in its isolated persistent WebKit origin; the native host additionally remembers document scroll position without injecting scripts.

Reading history and preferences stay on the device, independently keyed by repository, branch and file. Different editions never share a bookmark. The latest opened document is available through **Continue reading**. Cached content remains readable offline subject to the existing cache policy. The app does not write progress back to Git, import external websites, decrypt protected PDFs or add EPUB support in this change.

Settings → **File display → Hide files starting with a dot** hides dot-prefixed files and folders (including their descendants) in Directory, Reading, Search and recent commit file lists. It defaults to off, applies to all saved projects, takes effect immediately and persists on this device.
