# Build 15 physical-device review evidence

This checklist responds to Apple's 2026-09-29 Guideline 2.1 request. It concerns the frozen **1.0.0 (15)** submission, binary source `975aa4e`, not later development features.

## Recorded evidence and submission

- The original archive (source `975aa4e`) was signature-verified with Wei Dong's personal team DPK7SSB889 and installed in place, preserving app data. Fresh CoreDevice queries confirm **iPhone 17 / iOS 27.0.1 (24A446)** and **1.0.0 (15)**.
- The owner performed all phone gestures. QuickTime captured the physical device through **Screen → Roy**. No simulator, synthetic animation or automated touch is represented as physical evidence.
- Two reviewed clips were attached to the App Review reply sent **2026-09-29 at 15:16 Asia/Shanghai**. The sent message visibly lists both attachments. The six-part response was also saved in Review Notes (under 4,000 characters). Build 15 is still selected. No new binary was uploaded.
- `VaultReader-15-physical-demo.mp4`: **54 seconds**, **720×1566**, H.264, 30 fps, **4,853,601 bytes**, no audio. It opens from the Home Screen and shows sample Markdown/wikilinks, interactive HTML and offline Privacy.
- `VaultReader-15-reading-search-pdf.mp4`: **110 seconds**, same format, **7,327,448 bytes**, no audio. It shows sample library switching, reading list/contents, search, Markdown and its local image, relaunch, and native PDF page navigation.
- Each video is a continuous excerpt with the original action order preserved. Main uses seconds 0–54 of the second recording; supplement uses seconds 50–160 of the first. No segments were reordered or fabricated.
- The first raw capture later switches into unrelated private content. That tail and the second capture's unrelated system-settings tail are excluded. **Never upload either raw recording or private contact sheets.** Only the two named MP4 files are approved evidence candidates.
- All media and device evidence remain under ignored main `build/app-store/`. The recordings do not establish a fresh live private-repository sync, share transfer, or PDF close/reopen resume pass. The paired iPad was unavailable; its new physical QA remains outstanding. Earlier simulator coverage is separate.
- The owner requested richer English store screenshots after the reply was sent. Those are a separate public-facing preview task. Continued review/resubmission has not yet been requested; the submission still shows Unresolved Issues.

## Recording preparation

1. Verify the actual installed build is 15 and record the physical model/OS version in the evidence log. After the OS update, unlock and reconnect the phone.
2. Before recording, open Vault Reader and switch to **Try sample library** from Settings. Existing real connections stay saved; do not uninstall the app or delete a token. Verify that only `example/synthetic-vault` and original sample documents are visible.
3. Prefer English for reviewer clarity if convenient; Chinese is also a supported interface. Do not change the owner's global phone language. The app's language preference is under iOS Settings.
4. Return to the Home Screen. Close notifications and avoid filming account details, real repository names, private documents or tokens. Start the recording before launching Vault Reader. Only share the reviewed sample-only clip with Apple.
5. Record the physical iPhone screen via its built-in recorder or QuickTime's connected-device Screen source. A simulator recording is not equivalent. Keep a continuous, unaltered capture; an optional smaller encoding may be made without changing the demonstrated sequence.

## Suggested continuous flow (about 3–5 minutes)

| Step | Action in build 15 | Evidence to show |
| --- | --- | --- |
| 1 | Launch Vault Reader from the phone Home Screen | Actual app launch and sample library |
| 2 | Files → README.md → Guide.md / linked sample note | Markdown text, working links and local image |
| 3 | Files → Reader.html → Next page; leave and reopen | Interactive HTML and local persistence |
| 4 | Reading → example/synthetic-vault → Night Voyage → PDF | Native PDF navigation; move to page 2 |
| 5 | Go back and reopen the PDF | Same page resumes |
| 6 | Open the book's Markdown full text; adjust reading size/theme and use contents | Native reading controls and readable text |
| 7 | Search for a simple sample filename/body term; open a result | Build-15 search and document access; do not claim later search features |
| 8 | Recent → a sample commit | Original synthetic update list and changed files |
| 9 | Settings → Help / Privacy, then version footer | Offline documents and 1.0.0 (15) |
| 10 | Return Home and relaunch the app | Sample session persists |

There is no app-owned registration/login/account-deletion flow or paid content to demonstrate. Optional GitHub/GitLab access uses an existing provider account and read-only token; never include a real token in the video. This private document reader has no hosted public feed/chat or in-app reporting/blocking controls; the written response explains the scope rather than claiming controls that do not exist.

## Finish and submit

- Watch the entire real recording. Check legibility, version, launch, gestures, resume, no visible errors, and no personal data.
- Record the actual device, OS, filename, duration, resolution and tested flows. Do not treat install/launch alone as completed physical QA. Record iPad QA separately.
- Replace the pending item 1 in `review-notes.txt` and the unsent response with the actual clip reference and verified results. Keep App Review Notes below 4,000 characters.
- Upload the clip privately in the App Review conversation (or use an Apple-accessible link only if attachment limits require it). Send the complete six-part response, then request continued review of the same selected build 15 if appropriate. Do not replace its binary with the next unreleased batch.

Official references: [Apple screen recording](https://support.apple.com/en-au/102653), [QuickTime connected-device recording](https://support.apple.com/en-au/guide/quicktime-player/qtp356b55534/10.5/mac/26), [Apple current releases](https://support.apple.com/en-us/100100).
