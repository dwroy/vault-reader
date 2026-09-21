# Vault Reader

Read an Obsidian vault that lives in a (private) GitHub repository on your iPhone.

A native, read-only iOS app. No server, no account system: the app talks to the GitHub REST API directly with a fine-grained personal access token stored in the Keychain. Files are cached on disk by blob SHA, so anything you have opened once is available offline.

**Status: design stage (M0).** Nothing to build yet. Implementation-side architecture notes will land in `docs/ARCHITECTURE.md` together with the code.

## What it will do

- Home page = your vault's `README.md`; follow `[[wikilinks]]` and relative links from there, with native navigation.
- "Recent" = the repository's commit log, expandable, with links to the changed files.
- Search file names instantly; full-text search runs on-device. Spotlight integration planned.
- Renders markdown in a WKWebView (Obsidian flavour: wikilinks, embeds, callouts, block anchors, highlights, frontmatter tags). Images, PDFs, videos and spreadsheets open in Quick Look. Self-contained HTML files run in their own isolated origin with working `localStorage`.
- Face ID lock planned.

## What it will not do

- Edit, write or push.
- Act as a git client.
- Store anything anywhere except on your device.

## Stack

SwiftUI, iOS 18+, Swift 6, zero third-party Swift dependencies. Markdown rendering uses markdown-it and DOMPurify (vendored) inside a WKWebView, fed through a custom `vault://` URL scheme. The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`.

## Token

Create a fine-grained personal access token scoped to the single repository, with **Contents: Read-only** (Metadata: Read is added automatically). Paste it into the app's settings page. That is the only credential involved.

## License

MIT
