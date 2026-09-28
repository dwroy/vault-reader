# App Store release preparation

Owner decisions, 2026-09-28: release under Wei Dong's individual Apple Developer membership, free, outside China mainland and the European Union, with English as the default and 12 interface languages. The owner will handle the EU trader declaration before a later EU rollout. No paid features, subscriptions, ads, backend or new account system are introduced.

Candidate: **Vault Reader 1.0.0 (15)**, bundle ID `com.dwroy.vaultreader`, iOS/iPadOS 18+, iPhone and iPad. English is the app development/fallback language. The interface follows iOS language preferences and supports English, Simplified/Traditional Chinese, Japanese, Korean, Spanish, Brazilian Portuguese, French, German, Arabic, Hindi and Indonesian. Unsupported languages fall back to English; repository contents retain their original language. Samples and complete help/privacy documents are English and Chinese. Translations are AI-assisted, without a claim of professional native-speaker review.

The owner requested AI Native positioning and native Markdown/HTML/PDF support. The app does not provide built-in AI chat, generation or editing. Dedicated iPad split navigation and large-screen layout improvements remain deferred to the next version; current iPad compatibility is retained.

## Source and public URLs

- Store fields for all 12 languages are in their locale directories; fields have been checked against 30-character name/subtitle, 100-character keywords, 170-character promotional text and 4,000-character description limits.
- Privacy: https://github.com/dwroy/vault-reader/blob/main/docs/PRIVACY.md
- Support: https://github.com/dwroy/vault-reader/blob/main/docs/SUPPORT.md
- Contact: https://github.com/dwroy/vault-reader/issues
- The source repository is public with Issues enabled. The owner authorized the Git push. Both documents are now published on main and their public URLs returned HTTP 200 in the release check.
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

The owner completed the individual-team agreement. Build 14 was successfully exported, uploaded and processed under the verified Wei Dong personal team, **DPK7SSB889**. App Store Connect record **6816816892** has SKU `vault-reader-ios`, Productivity category and version **1.0.0**, with manual release selected. Build 15 replaces build 14 for the multilingual launch; its final archive/upload and review status are recorded below when completed.

All 12 localized names/subtitles and version descriptions, promotional text, keywords and support links have been saved. English-specific screenshots are being added because Apple requires them before switching the store's primary language from Simplified Chinese to English. The global age rating is 4+ (with Apple's regional equivalents), not Made for Kids. No broad user-content feed, chat, advertisements, unrestricted in-app web browser or app-supplied restricted content exists. HTML navigation only allows the current repository document; explicit external links open the system browser.

The owner confirmed completion of content rights, privacy accuracy and private review contacts. Content rights is now saved as Yes (necessary third-party rights). The App Privacy page visibly reports **Published** by the owner, with **Data Not Collected**. Review-contact fields are populated and remain only in App Store Connect, never in this repository.

Free pricing and availability were saved for **147 countries/regions**, excluding China mainland and all 27 EU members. Automatic inclusion of future territories is off. Apple silicon Mac and Vision Pro availability are off.

## Validation and outstanding gates

Detailed evidence is in `docs/ACCEPTANCE.md`. Completed development checks include 202 resource keys in 12 languages, all metadata lengths, 9 Node tests, 24 Swift package tests, 15 hosted tests, 10 existing Chinese UI flows, and the 12-language public-sample flow on both iPhone and iPad. A further hosted glyph test verifies offline Arabic/Devanagari fonts, and 8 final Release UI executions passed on both devices after that fix, including visually verified Arabic/Hindi document glyphs.

The owner's physical phone is currently unavailable. The last confirmed installed/launched app remains build 14; simulator coverage does not establish fresh private-repository synchronization, offline recovery, physical touch or attachment transfer. This limitation is carried into release acceptance rather than represented as a pass.

Final integration, archive/distribution checks, build selection, primary store language and App Review submission remain to be recorded below. A local build or saved metadata is not an uploaded or approved app.

## Official references checked

- https://developer.apple.com/app-store/review/guidelines/
- https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype
- https://developer.apple.com/news/upcoming-requirements/?id=04282026a
- https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/

## Release artifacts

- Development evidence: project-local `note-share` worktree, ignored `build/localization/`.
- Current screenshots: `build/localization/screenshots/iphone-6.9/` (1320×2868) and `ipad-13/` (2064×2752), synthetic content only, RGB PNG.
- Previous build 14 archive/export remains under main's ignored `build/app-store/` for traceability.
- Export/upload options use automatic signing, personal team DPK7SSB889 and `manageAppVersionAndBuildNumber=false`.
- No App Review submission or public availability is claimed until confirmed in the subsequent release record.
