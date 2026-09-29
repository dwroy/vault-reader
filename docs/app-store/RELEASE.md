# App Store release preparation

Owner decisions, 2026-09-28: release under Wei Dong's individual Apple Developer membership, free, outside China mainland and the European Union, with English as the default and 12 interface languages. The owner will handle the EU trader declaration before a later EU rollout. No paid features, subscriptions, ads, backend or new account system are introduced.

Submitted release (frozen): **Vault Reader 1.0.0 (15)**, bundle ID `com.dwroy.vaultreader`, iOS/iPadOS 18+, iPhone and iPad. English is the app development/fallback language. The interface follows iOS language preferences and supports English, Simplified/Traditional Chinese, Japanese, Korean, Spanish, Brazilian Portuguese, French, German, Arabic, Hindi and Indonesian. Unsupported languages fall back to English; repository contents retain their original language. Samples and complete help/privacy documents are English and Chinese. Translations are AI-assisted, without a claim of professional native-speaker review.

The owner requested AI Native positioning and native Markdown/HTML/PDF support. The app does not provide built-in AI chat, generation or editing. Dedicated iPad split navigation and large-screen layout improvements remain deferred to the next version; current iPad compatibility is retained.

## Version policy and next release

Owner instruction, 2026-09-28: **the submitted 1.0.0 (15) is fixed**. Its binary source is `975aa4e`; `e28bffd` records the submission. Preserve the build-15 archive/package and App Store selection. Do not replace, withdraw or resubmit it to include later feature work unless the owner explicitly reopens that release.

Post-submission features accumulate together in the **next release — unreleased, version number not yet assigned**:

- Search matching, ranking, snippets and in-document navigation (`abf4a5b`).
- Persistent prepared search text, SHA-based incremental updates and restart/repository-switch reuse (see `docs/ACCEPTANCE.md`).
- Compact title status, details/recovery controls and accessibility layout (`b1d7ca5`).
- Search/query preparation separation, bounded Markdown/TXT indexing, attachment/oversize metadata search and guidance for primarily non-text vaults (see `docs/ACCEPTANCE.md`).
- More conservative suitability guidance for note/PDF libraries and a persistent close button scoped to each vault.

The release boundary determines the next marketing version and upload build number after the batch is finalized. Individual feature changes do not each become a public release. Development builds 16, 17, 18 and 19 were installed locally for preview only; their `1.0.0` marketing label does not make their new code part of the frozen store release. None was uploaded. Future previews remain development artifacts; a device-build request is not permission to change the submitted release. Before archiving the next public candidate from main, explicitly set its new version and record the complete batch and source revision here.

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

The owner completed the individual-team agreement. Build 14 was successfully exported, uploaded and processed under the verified Wei Dong personal team, **DPK7SSB889**. App Store Connect record **6816816892** has SKU `vault-reader-ios`, Productivity category and version **1.0.0**, with manual release selected. Build 15 replaces build 14 for the multilingual launch. Its personal-team archive, export and upload succeeded; server processing reports Complete / Ready to Submit. **1.0.0 (15) was submitted on September 28 and rejected for supplemental information on September 29**, as recorded below.

All 12 localized names/subtitles and version descriptions, promotional text, keywords and support links have been saved. English-specific iPhone 6.9-inch and iPad 13-inch screenshots are uploaded, and the store primary language is now English (U.S.). Chinese screenshots retain their own set with the updated AI Native welcome screen; other locales inherit English screenshots. All saved descriptions/promotional text/keywords were checked against source. The global age rating is 4+ (with Apple's regional equivalents), not Made for Kids. No broad user-content feed, chat, advertisements, unrestricted in-app web browser or app-supplied restricted content exists. HTML navigation only allows the current repository document; explicit external links open the system browser.

The owner confirmed completion of content rights, privacy accuracy and private review contacts. Content rights is now saved as Yes (necessary third-party rights). The App Privacy page visibly reports **Published** by the owner, with **Data Not Collected**. Review-contact fields are populated and remain only in App Store Connect, never in this repository.

Free pricing and availability were saved for **147 countries/regions**, excluding China mainland and all 27 EU members. Automatic inclusion of future territories is off. Apple silicon Mac and Vision Pro availability are off.

## Validation and outstanding gates

Detailed evidence is in `docs/ACCEPTANCE.md`. Completed development checks include 202 resource keys in 12 languages, all metadata lengths, 9 Node tests, 24 Swift package tests, 15 hosted tests, 10 existing Chinese UI flows, and the 12-language public-sample flow on both iPhone and iPad. A further hosted glyph test verifies offline Arabic/Devanagari fonts, and 8 final Release UI executions passed on both devices after that fix, including visually verified Arabic/Hindi document glyphs.

At the build-15 release-validation checkpoint, the owner's physical phone was unavailable and build 14 was the last confirmed installed/launched app. Later development-device installations are recorded in `docs/ACCEPTANCE.md` and belong to the next-release batch; they do not extend the frozen build-15 acceptance. Simulator coverage and install/launch checks do not establish fresh private-repository synchronization, offline recovery, physical touch or attachment transfer.

Final integration, archive/distribution checks, upload, processing and primary store language are complete. Build 15 remains selected. The first submission was rejected under Guideline 2.1 for supplemental information. The six-part explanation and two latest-OS physical-device sample videos were delivered to Apple on September 29. Physical iPad and fresh private-network acceptance remain outstanding. Review approval and manual public release have not occurred.

## Official references checked

- https://developer.apple.com/app-store/review/guidelines/
- https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype
- https://developer.apple.com/news/upcoming-requirements/?id=04282026a
- https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/

## Release artifacts

- Development evidence: project-local `note-share` worktree, ignored `build/localization/`.
- Initial screenshots: `build/localization/screenshots/iphone-6.9/` (1320×2868) and `ipad-13/` (2064×2752), synthetic content only, RGB PNG. The approved September 29 English iPhone replacements are recorded below.
- Source: 975aa4e, integrated and pushed to main. Final archive: main `build/app-store/VaultReader-1.0.0-15.xcarchive`; distribution package: `build/app-store/export-15/VaultReader.ipa`. Previous build 14 artifacts remain for traceability.
- Export/upload options use automatic signing, personal team DPK7SSB889 and `manageAppVersionAndBuildNumber=false`.
- Review submission succeeded on **2026-09-28 at 14:54 Asia/Shanghai**. Status: **Waiting for Review**. Submission ID: `5cd6c637-8dfd-4771-a91d-2d6e93fe8bc5`.
- Review record: https://appstoreconnect.apple.com/apps/6816816892/distribution/reviewsubmissions/details/5cd6c637-8dfd-4771-a91d-2d6e93fe8bc5
- Main evidence: `build/app-store/submission-15.png`. All 10 newly added store locales now have their own policy URL; the completeness check passed after these were filled.
- Apple approval and public launch remain pending. **Manual release** is selected; approval alone does not publish the app.

## September 29 information request

Apple's message is “Guideline 2.1 — Information Needed — New App Submission.” The account has limited review history. The requested physical-device recording must begin with launching the app and show its typical flow on the latest OS. The other five items are purpose/audience, setup/access, external services, regional differences and relevant authorizations.

The submitted binary and selected build remain frozen at **1.0.0 (15)**. The original build was installed in place on the owner's iPhone, and fresh queries confirmed iOS 27.0.1 and build 15 after the OS update. The completed response text is retained in `review-response-draft.txt`; video provenance and acceptance limits are in `REVIEW-VIDEO.md`. Physical iPad QA remains outstanding.


### Supplemental response delivered

On **2026-09-29 at 15:16 Asia/Shanghai**, the six-part response and two reviewed physical-iPhone clips were sent privately in App Review. Both attachment filenames were verified in the sent message. Review Notes were saved with the completed information. See `REVIEW-VIDEO.md` for clip provenance, demonstrated flows and acceptance limits. Raw recordings are not uploadable because they contain unrelated tails; only the reviewed MP4 excerpts were supplied. **Build 15 remains selected; no binary replacement or upload occurred.** At that checkpoint the submission still showed Unresolved Issues. The owner then requested richer English store screenshot previews.


The owner approved the eight richer English iPhone screenshots and explicitly requested submission; see `SCREENSHOTS.md`. They show actual frozen-release UI with original local screenshot documents. No build replacement was required or performed.


### September 29 resubmission confirmed

At **15:58 Asia/Shanghai on 2026-09-29**, App Store Connect visibly confirmed **Waiting for Review** for the existing submission `5cd6c637-8dfd-4771-a91d-2d6e93fe8bc5`, version **1.0.0 (15)**. The eight approved English (U.S.) iPhone 6.9-inch screenshots were uploaded and reordered to match the approved gallery; the saved version page showed all eight in order. Review Notes retained the complete 3,983-character response, and the sent review message retained both physical-device MP4 attachments. Update Review and Resubmit to App Review both completed successfully. No binary was uploaded or replaced.

The manual-release setting was checked before resubmission and remains selected. Approval and public launch have not occurred. Existing iPad images and other locale-specific screenshot sets were not edited. Proof: main `build/app-store/resubmission-15-2026-09-29.png`; screenshot update proof: `english-screenshots-uploaded-2026-09-29.png` in the same ignored directory.
