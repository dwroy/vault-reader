# M1a acceptance — 2026-09-22

Platform order: iOS first, Android second. Implementation candidate; the full M1 acceptance gate is not yet closed.

## Verified

- 5 Node tests: link resolution, ambiguity ordering, relative paths/traversal, sanitizer, tree refresh, the same renderer bundle with iOS scheme and Android-style HTTPS resource prefixes.
- 7 Swift package tests: blob hash validation, pinned eviction and preview cleanup, corrupt/unsafe keys, ETag/304, distinct 401/rate-limit errors, truncated-tree rejection, directory ordering/deletions.
- 4 iPhone 17 / iOS 26.3 hosted tests: real Keychain create/update/read/delete, production WebKit renderer/sanitizer, refreshed tree re-resolving unchanged Markdown, localStorage host isolation and persistence across WebView recreation.
- 3 simulator UI tests: Home → index → note → image → QuickLook; Directory → note and Settings; a deliberately invalid token returns a real GitHub 401 and a recoverable settings message.
- Screenshot review: Chinese text renders correctly with bundled Noto Sans SC; native bars and banner no longer overlap; image preview has a visible Done control.
- Default Xcode ad-hoc simulator signing is required. An initial unsigned run produced Keychain error -34018; signed runs pass. No real credential was copied or used during these checks.

Total: 19 automated tests passed. Last complete iOS run: `build/DerivedData/Logs/Test/Test-VaultReader-2026.09.22_08-54-14-+0800.xcresult`. Screenshots are under `build/accepted-ui/`. These local artifacts are ignored by git.

## Real-vault link audit

Read-only scan of the current local notes checkout (`1f864c6`): 982 tracked files, 393 Markdown files. In prose (excluding code/frontmatter/comments): 1,766 wikilinks, 1,748 resolved and 18 unresolved; one duplicate Markdown basename group and zero ambiguous link occurrences under the implemented rule. Counts are a new snapshot and use the documented scanner scope; they are not assumed equivalent to the original design snapshot.

Detailed paths and unresolved targets are in ignored `build/link-audit.private.json`, not public source. The parser implements the design's same-directory → shortest-path → lexical rule. Its parity with actual Obsidian remains unverified; no passing unresolved-link threshold is claimed.

A separate offline simulator fixture imported 841 git-tracked Markdown/image blobs directly into the app container; the actual notes README rendered correctly. Inline code also uses the bundled CJK fallback. Screenshot: ignored `build/real-vault-home.private.png`. This did not use a token and is not a live private-GitHub sync test.

## Still required before calling M1 accepted

- Connect a user-supplied fine-grained read-only token to the private repository and verify initial sync, refresh and valid-token offline recovery end to end. Invalid-token behavior and mocked API branches are already verified.
- Compare the real unresolved links / same-name resolution with Obsidian.
- Measure the actual first-README latency against the 2-second target; UI test startup time is not a valid proxy.
- M1b: recent commits, local filename/full-text search, Markdown prefetch, isolated executable HTML views with kill/relaunch persistence, bounded WebView pooling/scroll restoration under deep navigation, remaining attachment/video handling, and physical iPhone acceptance.
- Personal developer-team selection, device signing/install/launch and touch/safe-area acceptance are pending. No device or Android build is claimed.

## Changes discovered during implementation

The repository already existed with README/LICENSE; its history was preserved. Development uses `.worktrees/m1a` and `codex/m1a`. The shared renderer was moved out of the iOS tree after the owner confirmed Android as the second platform. Its host adapter and versioned contract are separate from native data/security services. Font resources add about 4.5 MiB, remain local and carry their OFL notice.
