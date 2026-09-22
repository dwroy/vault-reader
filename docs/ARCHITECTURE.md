# Vault Reader architecture

Status: M1a implementation candidate, 2026-09-22. Product baseline: Vault Reader design v1. Platform order confirmed by the owner: **iOS first, Android second**.

## Three boundaries

```text
                 Shared reader-web (JavaScript + CSS)
          Markdown / wikilinks / anchors / sanitization / typesetting
                                  |
                  contracts/reader-v1.d.ts (version 1)
                       /                         \
            iOS native host                 Android native host (future)
     SwiftUI / WKWebView / QuickLook     Compose / WebView / system viewers
     VaultCore Swift package            Kotlin data adapters
     URLSession / disk / Keychain        HTTP / disk / Keystore
```

`packages/reader-web` has no UIKit, WebKit, Swift or Android dependency. It receives raw Markdown and a tree; it returns rendered content and three messages (`open`, `preview`, `height`). It does not fetch GitHub, persist app settings, navigate native screens, access tokens or manage downloads. The same bundled JS/CSS will ship in both apps. No CDN at runtime.

`packages/contracts` is the platform contract. Local files are repository-relative UTF-8 paths, not platform filesystem URLs. SHA identifies content; path identifies a note. The native host supplies resource URLs: `vault://file/` on iOS; Android should use [WebViewAssetLoader](https://developer.android.com/develop/ui/views/layout/webapps/load-local-content) and an origin-scoped [message listener](https://developer.android.com/develop/ui/views/layout/webapps/native-api-access-jsbridge), after its own storage/origin probe. Navigation links stay `vault://f/<encoded-path>#<anchor>` as a logical route; the native host interprets them. The native bridge adapter lives in `RendererWebView.swift`; the shared renderer never calls `window.webkit` directly.

`packages/VaultCore` is the **Apple implementation**, not an Android-shareable core. It has Foundation/CryptoKit and no SwiftUI, UIKit, WebKit, Security or QuickLook. Models, GitHub transport, tree indexes, cache integrity and metadata can be tested without an iOS simulator. Android will implement the small data layer in Kotlin against the same behavior below. Native UI, storage/security and system integration are separate on each platform. Do not introduce Kotlin Multiplatform, Rust FFI or a second app during M1 merely to maximize code sharing. If native sync logic grows materially during Android development, revisit sharing then, based on measured duplication.

## Data invariants for both apps

- Read-only GitHub REST requests; four concurrent requests globally, cancellable, explicit ETag/304 handling. Never send credentials to a renderer or external host.
- Branch head → complete recursive tree → immutable blob SHA. Reject truncated trees and keep the previous complete metadata.
- Verify Git blob SHA-1 (`blob <byte length>\0` + bytes) before writing. Refuse files over 100 MiB.
- Per-repository blobs; per-branch metadata. On iOS these directories use SHA-256 of the repository identity / branch, avoiding unsafe filenames and cross-repository collisions.
- Atomic writes; exclude renewable blobs from backup; device file protection on iOS. Native credential store keyed by repository; Android must use Keystore-backed credential encryption.
- Access-time eviction, default 500 MiB. Downloaded Markdown/SVG remain pinned even when over the limit. QuickLook copies are transient and cleared during eviction.
- Network failure keeps cache readable. 401 clears the active credential and opens settings; 403 permission denied is distinct from quota exhaustion. Editing settings validates the new credentials/tree before replacing the active repository.
- Path traversal cannot escape the vault; there is no `file://` path crossing the JS bridge.

## Current iOS implementation

`AppState` coordinates startup, refresh, repository changes and visible status. `VaultCore` owns transport/cache/index operations; `SchemeHandler` supplies bundled assets and cached/downloaded files. `RendererWebView` handles bridge validation, native pull-to-refresh, Dynamic Type and scroll restoration. `NoteView`/`DirView` own navigation and preview presentation. `SettingsView` uses Keychain through the iOS-only credential adapter.

The bundled renderer uses markdown-it, DOMPurify, footnotes and task lists. Noto Sans SC Variable (OFL, approximately 4.5 MiB) is bundled with Unicode-range font subsets for offline Chinese rendering on both platforms. The iOS simulator exhibited missing CJK glyphs with system-only CSS; a local font fixed the verified screenshot without depending on system font downloads. Source is in `packages/reader-web/src`; generated bundle and license notices are committed under `VaultReader/Resources/renderer`. Run `npm ci && npm run build:renderer` after source changes. The bundle is reusable by Android; packaging into Android assets is deferred until that app exists.

The M1a UI has Home and Directory. Recent/Search tabs, full Markdown prefetch, independent HTML reader views, bounded WebView pooling and device delivery remain M1b work. There are no empty placeholder tabs advertised as complete features. Image preview is already wired to QuickLook to validate the M1a image flow.

## Security and host integration

Native code injects `VaultHost` at document start. It only exposes a resource URL prefix and the three message methods. Messages are accepted only from the renderer main frame at `vault://app`; their URLs/paths are checked against the current index. Navigation outside initial renderer loading is canceled and routed natively. Raw HTML documents must use a separate WebView **without this bridge** in M1b.

DOMPurify removes executable markup and event attributes. Images allow only vault resources and HTTPS; style attributes are restricted to generated image widths, and SVG is never injected into the Markdown DOM. Code fences do not execute. Tree/Markdown are passed with `callAsyncJavaScript(arguments:)`, not interpolated into source code.

iOS 26.3 simulator probe passed: `localStorage` works at `vault://html-probe-a`, is invisible to host B, and survives recreation of a WebView at host A. App termination/relaunch and Android origin behavior are separate acceptance checks, still pending. No inference of Android storage compatibility from this iOS result.

Reference: Apple's [custom scheme handler](https://developer.apple.com/documentation/webkit/wkurlschemehandler) and WebKit's [persistent data store profiles](https://webkit.org/blog/14423/building-profiles-with-new-webkit-api/). GitHub protocol follows its [Git blobs API](https://docs.github.com/en/rest/git/blobs).

## Android entry criteria

Start after the iOS M1 reader is usable. First make a minimal Compose shell render the existing fixture with the unchanged JS bundle. Implement the three bridge messages and local asset handler, verify image loading and storage isolation, then add Kotlin GitHub/cache/credential adapters. Run shared link fixtures on the same renderer and platform-native tests for HTTP, disk and security. Add Android UI/system features only after these contracts pass. iOS M2 features must not expand the shared bridge without a versioned contract change.

## Validation boundaries

Synthetic fixtures are public and committed. Real-vault link audit output and screenshots live only under ignored `build/`. The regression CLI reads only git-tracked paths, excludes code examples and Obsidian comments, and produces unresolved/ambiguous reports. It does not claim an Obsidian parity threshold until a real Obsidian comparison has been performed. Token-requiring private GitHub access and true device acceptance are separate from synthetic simulator tests.
