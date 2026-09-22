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

## Real local vault

Read-only audit snapshot (11:04): 984 git-tracked files, 393 Markdown files, 1,766 prose wikilinks, 1,748 resolved, 18 unresolved, one duplicate Markdown basename group and zero ambiguous link occurrences. Code/frontmatter/comments are excluded. The only tracked duplicate group is five README files; Obsidian's quick switcher was checked for that group. This is not a complete resolver-parity or unresolved-link-baseline comparison. Obsidian can also see files outside the tracked-file scope, so its total cannot be substituted directly.

841 tracked Markdown/image blobs were imported into the simulator cache. The actual README renders with Chinese glyphs and four native tabs; screenshot is `build/acceptance/real-home.private.png`. The initial measured cached run took 2.576 seconds. After deferring Markdown completion until the home render, the actual cached README measured **1.548 seconds** (process 96134 in `home-timing-after-prefetch.private.log`). This measures AppState creation through font-ready rendering on the simulator; OS launch animation, device cold launch and first online sync are separate timing gates. It is offline cache evidence, not GitHub synchronization evidence.

## Remaining gates

- Valid fine-grained read-only token entered through the app's secure Settings UI: initial private-repository sync, refresh, 30 real commits and valid-token offline recovery. Never request the token in chat.
- Verify the README 2-second target for a full physical-device launch with a documented connection/cache state; measure full-text search on the real phone/corpus.
- Complete Obsidian parity checks with matching tracked-file scope; no unresolved-link threshold has passed yet.
- Open the user's actual large HTML reader, PDF/video attachments and exercise real download progress/cancel/large-file handling. Synthetic HTML and SVG QuickLook do not replace these checks.

M2/M3 and Android implementation remain out of scope. M1a's earlier 19-test baseline and real-cache screenshots are preserved in the M1a worktree's ignored build directory.
