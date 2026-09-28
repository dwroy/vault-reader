# App Store release preparation

Owner decisions, 2026-09-28: release under Wei Dong's individual Apple Developer membership, free, outside China mainland and the European Union, retaining Simplified Chinese. The owner will handle the EU trader declaration before a later EU rollout. No paid features, subscriptions, ads, backend or new account system are introduced.

Candidate: Vault Reader 1.0.0 (14), bundle ID `com.dwroy.vaultreader`, iOS/iPadOS 18+, iPhone and iPad. The app interface is primarily Simplified Chinese; English store text explicitly states this. Existing approved branding is retained.

## Source and public URLs

- Chinese and English fields are in `zh-Hans/` and `en-US/`; fields have been checked against 30-character name/subtitle, 100-character keywords, 170-character promotional text and 4,000-character description limits.
- Privacy: https://github.com/dwroy/vault-reader/blob/main/docs/PRIVACY.md
- Support: https://github.com/dwroy/vault-reader/blob/main/docs/SUPPORT.md
- Contact: https://github.com/dwroy/vault-reader/issues
- The source repository is public with Issues enabled. The new policy and support documents must be published to main before these two URLs can be entered as working submission URLs. Git push requires owner authorization per AGENTS.md.
- The same Markdown documents are bundled for offline access on the welcome screen and in Settings.

## Review access

See `review-notes.txt`. The publicly accessible sample-library button exists in Release; it is not a hidden launch argument. Reviewers can use reading, search, local resume, HTML, PDF, synthetic commits, sharing and repository switching without credentials. Sample files, reading state and HTML origins are isolated from real repositories. The sample session persists across relaunch and can be exited in Settings.

Actual remote repository synchronization still requires a valid read-only provider token. A sample-mode pass does not prove private-repository synchronization. If App Review requires live repository access, provide a dedicated synthetic test repository and revocable read-only credential via App Store Connect's private review fields; never a personal vault or a token in Git. Do not claim that Apple has approved a demo-mode exception.

## Privacy assessment

No developer-operated backend, analytics/advertising SDK, tracking identifier or telemetry upload was found in this source audit. Suggested App Privacy response: no data collected by the developer, subject to completing the actual App Store Connect questionnaire and checking its definitions. This is not a claim of no network traffic: the selected Git provider receives authenticated requests; user-supplied HTML, external images, browser links and user-directed sharing can contact other services. These behaviors are disclosed in the policy.

Required-reason API declarations shipped in `PrivacyInfo.xcprivacy`:

- UserDefaults / CA92.1: app-only profiles and preferences.
- FileTimestamp / C617.1: file metadata inside the app container, for cache eviction and size accounting.
- SystemBootTime / 35F9.1: elapsed time between app launch and initial rendering.

`ITSAppUsesNonExemptEncryption` is false: app transport/security uses operating-system HTTPS and Keychain; CryptoKit is used for hashes, not a custom encryption implementation. Reassess if transport or cryptography changes. No App Tracking Transparency prompt is needed for the current non-tracking implementation.

## Account and distribution checks

App Store Connect was accessed and switched from CyberGame Limited to Wei Dong's individual provider. The personal provider has no existing app records. Creating an app is currently blocked by the updated Apple Developer Program License Agreement; the account holder has been asked to review and accept it. EU distribution additionally needs the trader-status declaration or exclusion of EU territories, based on the owner's answer.

When those account requirements are cleared: create the app with the existing bundle ID, Simplified Chinese primary language, SKU `vault-reader-ios`, Productivity category, price 0, approved territories and manual release. Review the current age-rating questionnaire based on actual features: no social network, public UGC feed, messaging, ads, purchases or app-supplied restricted content; do not invent a rating before completing the questionnaire. Set content-rights answers based on the original synthetic samples and users' own repository files.

## Validation and outstanding gates

Record current execution results in `docs/ACCEPTANCE.md`. Required release gates:

- Release iPhone and iPad UI runs using the public sample entry, relaunch, sample exit, offline policy and help.
- Swift data/host regressions for storage isolation and existing reader behavior.
- Fresh physical-device private repository first sync, refresh, cached offline recovery, reading/touch and actual attachment transfer; the phone was unavailable at the initial check.
- Review screenshots containing only synthetic samples, at accepted iPhone and iPad dimensions.
- Integrate verified code into local main and archive with the verified individual signing team. Main's prior build signature confirms the personal team; its current account/certificate status still needs distribution validation.
- Upload and server-side validation in App Store Connect, TestFlight processing, final privacy/age-rating/region review and submission. A local build is not an uploaded or approved app.

## Official references checked

- https://developer.apple.com/app-store/review/guidelines/
- https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype
- https://developer.apple.com/news/upcoming-requirements/?id=04282026a
- https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/

## Prepared handoff artifacts

- Final source: 372f8d4 (plus documentation-only status commits).
- Local main archive: `build/app-store/VaultReader-1.0.0-14-final.xcarchive`.
- Export options: `build/app-store/ExportOptions.plist`, automatic signing, verified personal team, destination `export` (not upload).
- Selected raw screenshots: `build/app-store/screenshots/iphone-6.9/` and `build/app-store/screenshots/ipad-13/`; identical originals remain in the development worktree with the `.xcresult` evidence.
- Archive and strict signature/bundle checks passed. App Store `.ipa` export failed because Xcode has no Apple Account configured and cannot obtain a distribution profile. Xcode's login dialog has been opened for the owner. The developer agreement still blocked App Store Connect at the final refresh. These are external account blockers, not a completed submission.
- Required next actions: finish the individual-team agreement and Xcode login, authorize Git push to publish policy/support URLs, connect the phone for fresh real-device acceptance, then create the App Store record/export/upload and verify server-side processing. Price and territory changes must follow the confirmed free/non-mainland/non-EU plan. Use manual release.
