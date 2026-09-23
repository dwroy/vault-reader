# M1 acceptance — 2026-09-22

M1b implementation candidate, extended by the owner’s explicit requests for saved repositories and GitLab. iOS first, Android second. **The full M1 gate remains open.** No private-repository online sync is claimed without a valid read-only credential.

## Automated verification

- 5 Node renderer/link tests pass; the shared JS/CSS and bridge contract are unchanged in M1b.
- 15 Swift package tests pass: existing cache/transport/index checks plus commit branch/ETag/pagination, renamed/deleted files, filename/Chinese full-text search, SHA invalidation, cancellation-safe error handling, Chinese offline recovery, preview survival when pinned content exceeds the cache limit, saved-profile persistence, GitLab request/namespace/pagination/date mapping, legacy GitHub migration and cross-host identity isolation.
- A synthetic corpus over 5 MB / 400 documents scans in approximately 8 ms on this Mac in the latest Debug package run, under the 200 ms budget. This is not an iPhone or real-vault search measurement.
- Simulator hosted checks cover Keychain, production renderer/sanitization, refreshed link trees, production HTML origins with no bridge, file/repository storage isolation, cached Markdown pause/resume/deletion, twelve-level navigation with scroll restoration, and switching identical paths between independently cached repositories.
- Simulator UI checks cover Home → wikilink → image → QuickLook, Directory/Settings, real invalid-token 401, filename/full-text Search, Recent → changed file, and HTML page 3 surviving app termination/relaunch while another HTML file stays on page 1. Added UI coverage checks saved-vault switching and GitLab server/namespace fields.

The twelve-level navigation test now selects the expected route in its own UIWindowScene. Earlier tests mistakenly selected an outgoing page during the return animation. The corrected test verifies the original reading session, at most three live weak WKWebView references during transitions, and restoration to 700 points (8-point tolerance). Offscreen animation-frame waits exposed a separate real retention bug; bounded cancellable native waits fixed it.

Local evidence is under ignored `build/acceptance/` and `build/DerivedData/Logs/Test/`. The complete simulator run passed all 15 hosted/UI tests: `build/DerivedData/Logs/Test/Test-VaultReader-2026.09.22_11-38-21-+0800.xcresult`. Combined with 15 package tests and 5 Node tests, 35 distinct automated checks pass. Real paths, screenshots, raw reports and credentials are never committed.

## Live GitLab adapter probe

The production Swift GitLab adapter was compiled into a local public-data probe and used without credentials against GitLab’s official `gitlab-org/cli` project. It retrieved 1,591 file entries across paginated tree requests, downloaded the 13,785-byte README and verified its exact Git blob SHA, fetched 30 recent commits, and opened a three-file commit diff. Evidence: ignored `build/acceptance/gitlab-public-smoke.log`. This verifies a public GitLab.com connection from the Mac; private GitLab, self-managed deployments and iPhone networking still require their own acceptance.

## Physical iPhone

A development build was signed with the **Wei Dong Individual team**, installed and launched on iPhone 17 / iOS 26.6.1. The generated app's code signature and embedded provisioning profile were checked: both identify the personal team, not CyberGame Limited. The profile expires 2027-03-16. No developer team ID is committed.

The final physical-device matrix passed all 15 checks across a complete run and a targeted network rerun: eight hosted tests (including independent repository caches and corrected twelve-level scroll restoration), six UI flows, and the real invalid-token 401 check. Source/UI coverage includes GitLab settings, saved-repository switching, Search/Recent, image QuickLook and HTML kill/relaunch persistence. Screenshots of Home, safe areas, native bars and QuickLook were inspected under `build/acceptance/device-final-ui/`.

The initial network check reported the phone as offline. After the user confirmed wireless-data permissions and reconnected/unlocked the phone, the targeted network rerun reached GitHub and passed the 401 assertion (`build/acceptance/device-network-final.log`). No valid private-repository token was used.

USB was unplugged during follow-up work. Xcode’s explicit Wi-Fi Connect remained unavailable; a re-pair attempt was initially blocked by automatic approval review, then explicitly authorized by the user, but returned CoreDevice error 4000. The user later reconnected successfully via **USB**, confirmed by `transportType: wired`. Wireless debugging is not claimed. The final source is integrated and built locally; installation status is recorded in the handoff.

## Branding and navigation follow-up

The original open-book/bookmark identity is now packaged as default, dark and tinted 1024 px app icons and scalable native light/dark logos. All app-icon PNGs are opaque. Xcode compiled the catalog and generated iPhone/iPad icon metadata. The clean simulator's Home Screen icon was visually checked and tapped to launch; welcome and Settings logos were inspected in light/dark UI.

At the owner's request, the tab order is now **Directory → Recent → Search → Settings**, with Directory selected initially and no Home tab. The vault menu moved to Directory. Settings retains the reading stack when changing tabs, and choosing a saved vault returns to Directory. The obsolete home-file input and connection requirement were removed; foreground Markdown completion no longer waits for home rendering. The directory uses an inline title after visual inspection exposed an empty large-title area.

All seven updated simulator UI flows and the hosted cached-Markdown completion regression passed (8 checks): tab order/default selection, opening notes/wikilinks/images from Directory, Settings and returning to the same note, GitLab setup, HTML termination/relaunch persistence, invalid-token recovery, saved-vault switching, and Search/Recent. A subsequent simulator build and visual check verified the inline-title adjustment. Manual simulator interaction additionally verified that selecting a saved profile in the Settings tab returns to Directory. Evidence is in `.worktrees/brand-assets/build/acceptance/` (ignored).

The main-checkout **0.2.0 (4)** build was signed with the Wei Dong personal team, passed strict code-signature verification, and was installed and launched on the iPhone through USB. Fresh physical-device screenshots verified the new Home Screen icon and final Directory screen with the four requested tabs; the existing 984-file vault remained available after the update. The owner reported the Token connection working after correcting Contents read permission. This does not independently close the full private-sync/performance gates below. This navigation follow-up used simulator interaction tests plus real-device installation/launch/screenshots, not a new physical touch suite.

At the owner's request, `com.dwroy.vaultreader.uitests.xctrunner` was uninstalled from the phone. A final exact bundle-ID query returned no matching app. The reader and its credentials were retained. Main evidence: ignored `build/acceptance/directory-tabs-device-build.log`, `directory-tabs-usb-install.json`, `directory-tabs-usb-launch.json`, `directory-tabs-final.private.png`, and `final-test-runner-check.json`.

## Real local vault

Read-only audit snapshot (11:04): 984 git-tracked files, 393 Markdown files, 1,766 prose wikilinks, 1,748 resolved, 18 unresolved, one duplicate Markdown basename group and zero ambiguous link occurrences. Code/frontmatter/comments are excluded. The only tracked duplicate group is five README files; Obsidian's quick switcher was checked for that group. This is not a complete resolver-parity or unresolved-link-baseline comparison. Obsidian can also see files outside the tracked-file scope, so its total cannot be substituted directly.

841 tracked Markdown/image blobs were imported into the simulator cache. The actual README renders with Chinese glyphs and four native tabs; screenshot is `build/acceptance/real-home.private.png`. The initial measured cached run took 2.576 seconds. After deferring Markdown completion until the home render, the actual cached README measured **1.548 seconds** (process 96134 in `home-timing-after-prefetch.private.log`). This measures AppState creation through font-ready rendering on the simulator; OS launch animation, device cold launch and first online sync are separate timing gates. It is offline cache evidence, not GitHub synchronization evidence.

## Remaining gates

- Valid fine-grained read-only token entered through the app's secure Settings UI: initial private-repository sync, refresh, 30 real commits and valid-token offline recovery. Never request the token in chat.
- Rebaseline first-screen timing for the new Directory entry with a documented connection/cache state; the earlier README render timing is historical and is not the current startup measurement. Measure full-text search on the real phone/corpus.
- Complete Obsidian parity checks with matching tracked-file scope; no unresolved-link threshold has passed yet.
- Open the user's actual large HTML reader, PDF/video attachments and exercise real download progress/cancel/large-file handling. Synthetic HTML and SVG QuickLook do not replace these checks.

M2/M3 and Android implementation remain out of scope. M1a's earlier 19-test baseline and real-cache screenshots are preserved in the M1a worktree's ignored build directory.

## Reading extension — local acceptance

The owner requested an independent Reading tab for books, papers and articles, then a project → content hierarchy. The implemented interpretation of project is an existing saved repository/branch. Tab order is now Directory → Reading → Recent → Search → Settings. Original/condensed/HTML editions are listed together under their book folder; native progress is isolated by project and file.

- 8 Node renderer/link tests and 18 Swift package tests pass. New cases cover relative indexed PDF discovery, rejected external/traversing targets, edition separation, bounded history, duplicate headings, reflow restoration and protection against delayed first-frame scroll overriding a bookmark.
- All 9 hosted iOS checks and 9 UI flows passed across a full regression and targeted reruns. New UI flows verify Markdown force-quit/relaunch to the same chapter, larger-font reflow, a distinct condensed edition starting independently, PDF page 3 surviving relaunch, and switching to a second project without leaking progress. Existing navigation, search/recent, GitLab, invalid-token recovery, HTML page state and WebView lifetime coverage remain in use.
- An old HTML UI check initially failed because added synthetic fixtures put the target below the viewport; its helper now scrolls to the file and the HTML persistence check passes. A real Markdown restoration race was subsequently fixed: a deferred initial animation frame could overwrite native restoration. Its new Node regression plus the Markdown resume and twelve-level WebView checks passed after the fix. Logs are under the book-reader worktree's ignored `build/acceptance/`.
- Real local acceptance used a separate simulator cache containing 450 reading files/dependencies (50,522,783 bytes) with their Git blob hashes verified. Screenshots confirm initial rendering of the 750,751-byte long Markdown original, a 380-page scanned PDF, and an existing 11-section HTML reader. Four linked book PDFs opened through PDFKit (372, 296, 380 and 249 pages). No real books, screenshots, reading history or private manifests are committed.

The integrated main-checkout **0.2.0 (5)** device app built successfully with the confirmed Wei Dong personal team (DPK7SSB889) and passed `codesign --verify --deep --strict`. Its source commit is `561291a`; build evidence is in main's ignored `build/acceptance/reading-device-build.log`, and the app is `build/M1bDevice/Build/Products/Debug-iphoneos/VaultReader.app`.

Mac locking prevented additional manual desktop interaction. A fresh CoreDevice check after the build still listed the iPhone as unavailable, so build 5 was **not installed** and build 4 remains the last confirmed phone version. Installation and physical-device reading/touch acceptance are pending USB reconnection. Synthetic simulator resume tests and real-file initial rendering do not claim a completed physical-device reading/touch pass or the full private-network/performance gates.


## Directory toolbar follow-up

At the owner's request, the project switcher is back on Directory's leading side and the trailing ellipsis menu exposes Refresh. Nested directories retain their native back button and Refresh menu; the existing note action menu is unchanged. Both existing simulator flows for Directory/Settings navigation and saved-project switching passed (2 checks, zero failures). A synthetic simulator screenshot visually confirms the final leading logo switcher and trailing ellipsis button. Evidence: the book-reader worktree's ignored `build/acceptance/directory-toolbar-tests.log` and `directory-toolbar.png`. Mac locking prevented an additional manual menu interaction; these checks do not claim a fresh online-sync test.

Main's **0.2.0 (6)** app, source commit `e952b47`, built with the Wei Dong personal team and passed strict signature verification (`build/acceptance/toolbar-device-build.log`). A fresh CoreDevice query still reports the iPhone as unavailable; no device installation was attempted and build 4 remains the last confirmed installed phone version. This build includes the Reading extension as well as the toolbar correction.

## File display preference follow-up

Settings now offers **Hide files starting with a dot**, defaulting to off. It persists on this device, applies immediately to all saved projects, and filters dot-prefixed files, folders and their descendants from Directory, Reading (including continue/recent reading), filename/full-text search results, and recent commit file lists. The underlying tree is retained for content/link resolution.

Three existing simulator flows passed: Directory/Settings navigation, Search/Recent files, and PDF resume with project isolation. The exported Settings screenshot confirms the new switch and its description fit the iPhone layout. Evidence lives in the book-reader worktree's ignored `build/acceptance/file-display-tests.log` and `file-display-attachments/`. The Mac was locked, so this pass does not claim an additional manual toggle/relaunch acceptance. The iPhone is still unavailable for device installation.

Main source `a5d61e6` produced **0.2.0 (7)** with the Wei Dong personal team; the app passed strict signature verification. Build log: ignored `build/acceptance/file-display-device-build.log`. No phone installation occurred; build 4 is still the last confirmed installed version.


## USB installation — 2026-09-23

After the owner reconnected the iPhone, CoreDevice reported Roy connected and unlocked. The existing integrated **0.2.0 (7)** app passed strict signature verification again, with the confirmed Wei Dong personal team (DPK7SSB889). It was installed over the existing reader through USB without uninstalling the app, then successfully launched. A fresh installed-app query confirmed marketing version 0.2.0 and bundle version 7. An exact query for `com.dwroy.vaultreader.uitests.xctrunner` returned no matching app; the test runner was not reinstalled.

Main's ignored evidence: `build/acceptance/reader-v7-usb-install.json`, `reader-v7-usb-launch.json`, `reader-v7-installed-app.json`, and `reader-v7-runner-check.json`. This closes the pending build-7 installation and launch gate; it does not claim a new physical-device reading, touch, toggle/relaunch or network-sync acceptance pass. The earlier build-4 "last installed" statements are historical; build 7 is now the latest confirmed installed version.

## Reading list follow-up

At the owner's request, Reading now follows an explicit reading-list Markdown instead of guessing books from folders, and recent reading is limited to the three most recent Markdown documents. Imported PDFs and HTML readers no longer appear in Continue/Recent reading; their saved positions remain available from each book page. The owner then asked for a vault-independent format: the root README's `书单`/`booklist` frontmatter now names the list files in any layout, with conventional `书单.md`/`booklist.md` names and reading folders as fallbacks. The format is specified in [READING-LIST.md](READING-LIST.md).

- 23 Swift package tests pass, including new cases for README declarations (scalar, YAML list, flow list, quoted wikilink, Markdown link, BOM; body lines, missing, traversing and non-Markdown targets ignored), conventional names found in any folder, the Markdown-only three-item recent list, group/book parsing, every file role, multi-link and indented items, escaped wikilink pipes, code fences, shallow-path wikilink precedence matching the renderer, external links, missing targets, traversal and unsupported schemes.
- The full iOS 26.3 simulator suite passed (9 hosted checks and 9 UI flows), as did 8 Node renderer/link tests. The book flows now cover Markdown chapter resume/reflow through the book page and PDF page 3 surviving relaunch while the PDF stays out of Continue/Recent reading and project progress stays isolated. The synthetic demo list now uses the new format at `书架/我的书单.md`, outside every reading folder and under an unconventional name, so the flows only pass if the README declaration is honoured. Evidence is in the book-list worktree's ignored `build/acceptance/` (`book-list-readme-tests.log`, `book-list-attachments/`).
- The owner's real reading list was restructured in the notes vault (not in this repository). Its README now declares `书单: study/read/书单.md`. A local VaultCore check against the vault's tracked paths resolved that declaration, parsed all 8 books, resolved all 20 file links, and found no reading-folder file missing from the list. That output was not committed.

These checks do not claim a physical-device reading pass or a network refresh of the updated list on the phone.

Main source `a6db3ce` produced **0.2.0 (8)** with the Wei Dong personal team (DPK7SSB889); the app passed strict signature verification (`build/acceptance/book-list-device-build.log`). It was installed over USB on the iPhone, and the device now reports 0.2.0 (8) (`reader-v8-usb-install.json`, `reader-v8-installed-app.json`). A remote launch was refused because the phone was locked (`reader-v8-usb-launch.json`), so this build has no confirmed device launch or on-device reading-list pass yet.
