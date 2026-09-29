# English screenshot candidates - 2026-09-29

The owner requested richer English store screenshots showing life, family, children and park notes. Eight full-frame iPhone 17 Pro Max simulator screenshots were prepared, 1320 x 2868 RGB PNG without transparency.

## Provenance

- UI, renderer and native behavior: frozen source `975aa4e` (release 1.0.0 build 15).
- A local ignored source snapshot was built for the simulator. Only `EnglishSamples.swift` and the synthetic PDF data in `BookDemoFixtures.swift` differ from that source; a complete tracked-file hash comparison verified this boundary. The simulator build succeeded.
- The screenshot examples include original English Markdown, HTML, an original five-page PDF story and the existing original leaf illustration. They contain no private vault data or commercial book text. The expanded fixtures are not claimed to be bundled in the submitted app.
- App interactions and links were checked in the simulator, and every final frame was visually inspected. Native screenshots were converted from opaque RGBA to RGB without retouching the UI, then packaged. This is screenshot preparation, not fresh physical-device acceptance.
- No binary, feature or screenshot has been uploaded as part of this preview task. Existing iPad store images remain unchanged. The owner has been asked whether to use these eight images before updating the public listing and resubmitting build 15.

## Suggested gallery order

1. Knowledge-library Markdown home.
2. A day in the park: image, highlights and everyday notes.
3. Directory with Books, Family, Life, Reading and Reports.
4. Family index: childhood questions, first bike ride, kitchen garden and shared days.
5. Long-form Markdown reading.
6. Original interactive HTML field guide.
7. Native PDF reading.
8. Book detail: reading notes, Markdown full text and original PDF.

## Local artifacts

All screenshots, previews and fixtures are ignored under main `build/app-store/english-screenshots-2026-09-29/`:

- `iphone/`: eight original RGB PNG files.
- `gallery.jpg`: comparison contact sheet only; not a store upload.
- `index.html`: local interactive gallery with click-to-enlarge.
- `VaultReader-English-iPhone-Screenshots.zip`: original images, README and manifest.
- `manifest.json`: image hashes, dimensions and source boundary.
- `fixtures/`: retained source generators and original English documents.

Build log: `build/app-store/english-screenshot-build.log`. The submitted build remains 15. App Review videos are separate private attachments, not public store preview videos.

Dimensions were checked against [Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).
