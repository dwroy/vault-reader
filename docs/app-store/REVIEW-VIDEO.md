# Build 15 physical-device review evidence

This checklist responds to Apple's 2026-09-29 Guideline 2.1 request. It concerns the frozen **1.0.0 (15)** submission, binary source `975aa4e`, not later development features.

## Current preparation

- The original main archive was signature-verified with Wei Dong's personal team DPK7SSB889 and installed in place on the connected iPhone 17. The installed-app query confirms 1.0.0 (15). No uninstall or data deletion was performed.
- The connected phone reports iOS **26.6.1**. Apple's current release page lists iOS **27.0.1**, released September 28. Apple's rejection specifically requests the latest OS; the owner has been asked to complete the system update. No latest-OS compliance or finished recording is claimed yet.
- The paired iPad is unavailable. Its new physical-device QA remains outstanding.
- Review Notes cover items 2–6 and explicitly mark the video pending. `review-response-draft.txt` is not ready to send until the actual video and device details are added.
- Private device logs, screenshots and videos belong under ignored `build/app-store/`, never in Git.

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
