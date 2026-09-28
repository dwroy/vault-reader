# App Store release preparation

Owner decisions, 2026-09-28: release under Wei Dong's individual Apple Developer membership, free, outside China mainland and the European Union, retaining Simplified Chinese. The owner will handle the EU trader declaration before a later EU rollout. No paid features, subscriptions, ads, backend or new account system are introduced.

Candidate: Vault Reader 1.0.0 (14), bundle ID `com.dwroy.vaultreader`, iOS/iPadOS 18+, iPhone and iPad. The app interface is primarily Simplified Chinese; English store text explicitly states this. The owner requested AI Native positioning and native Markdown/HTML/PDF support in the listing. Store name: Vault Reader: AI Native. In-app artwork is unchanged. Dedicated iPad split navigation and large-screen layout improvements are deferred to the next version; the current iPad-compatible build remains in this release.

## Source and public URLs

- Chinese and English fields are in `zh-Hans/` and `en-US/`; fields have been checked against 30-character name/subtitle, 100-character keywords, 170-character promotional text and 4,000-character description limits.
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

The owner completed the individual-team agreement. Distribution export and upload succeeded with the verified Wei Dong personal team. App Store Connect record **6816816892** now exists with SKU `vault-reader-ios`, primary language Simplified Chinese, Productivity category and version **1.0.0 (14)**. Build 14 completed processing and was selected for the version. Manual release is selected.

Chinese and English (U.S.) AI Native metadata, names and subtitles have been saved. Four synthetic screenshots are uploaded for each of iPhone 6.9-inch and iPad 13-inch. The questionnaire calculated a global 4+ age rating (with Apple's regional equivalents); the app is not categorized as Made for Kids. No broad user-content feed, chat, advertisements, unrestricted in-app web browser or app-supplied restricted content exists. HTML navigation only allows the current repository document; explicit external links open the system browser.

Content rights: the application bundles original synthetic samples and reads repositories selected and authorized by users. The proposed third-party-content rights statement is awaiting the owner's explicit confirmation after automatic approval review blocked saving that specific legal declaration. No acceptance is claimed. Review-contact details and publication of the App Privacy accuracy declaration also remain owner-confirmation items. Automatic approval review subsequently prevented Add for Review while those prerequisites remain unresolved; no review-staging or submission result is claimed. Contact details are kept only in App Store Connect, never in this repository.

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
- Archive and strict signature/bundle checks passed. After the owner resolved the personal-team agreement, `build/app-store/export/VaultReader.ipa` exported successfully and `build/app-store/upload.log` confirmed `Uploaded VaultReader` / `EXPORT SUCCEEDED`. Server-side processing completed and build 14 is selectable in App Store Connect.
- The final archived app was installed over the owner's existing iPhone app without deleting its profile or cache. A fresh installed-app query confirms 1.0.0 (14), and remote launch succeeded after unlocking (`device-installed-14.json`, `device-launch-unlocked.json`).
- The opt-in real repository XCTest could not start: Xcode did not expose the physical phone as a test destination although CoreDevice installation/launch worked. The unexecuted diagnostic source and logs are retained under ignored `build/app-store/`; they are not included in release source. No new physical private-sync, offline recovery or manual touch acceptance is claimed.
- No App Review submission or public release has occurred yet. Complete the remaining store settings, owner-confirmed declarations/contact information, and submission validation. Free pricing was confirmed after configuring availability. The 147 selected countries/regions exclude China mainland and all 27 EU members; all 28 excluded regions were visibly Not Available. Automatic inclusion of future App Store territories is off. Apple silicon Mac and Vision Pro availability are off for this initial iOS/iPadOS release.
