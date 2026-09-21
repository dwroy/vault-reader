# Vault Reader

Read an Obsidian vault that lives in a (private) GitHub repository from your phone.

A single-page, read-only PWA. No server, no build step, no account system: the app talks to the GitHub REST API directly with a fine-grained personal access token that never leaves your device. Files are cached locally by blob SHA, so anything you have opened once is available offline.

**Status: design stage (M0).** Nothing to run yet. The design document currently lives in the author's private notes; the implementation-side architecture notes will land in `docs/ARCHITECTURE.md` together with the code.

## What it will do

- Home page = your vault's `README.md`; follow `[[wikilinks]]` and relative links from there.
- "Recent" = the repository's commit log, expandable, with links to the changed files.
- Search file names instantly; full-text search runs on-device over all markdown.
- Renders markdown (Obsidian flavour: wikilinks, embeds, callouts, block anchors, highlights, frontmatter tags), images, self-contained HTML files (sandboxed, with a localStorage shim), PDFs and videos.
- Installs to the iOS home screen as a standalone web app.

## What it will not do

- Edit, write or push.
- Sync files to your phone's file system.
- Store anything anywhere except your browser.

## Token

Create a fine-grained personal access token scoped to the single repository, with **Contents: Read-only** (Metadata: Read is added automatically). Paste it into the app's settings page. That is the only credential involved.

## License

MIT
