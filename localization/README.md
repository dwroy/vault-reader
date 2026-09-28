# Language resources

English is the development and fallback language. The app follows the user's iOS preferred language, including the per-app language setting. Supported locales: en, zh-Hans, zh-Hant, ja, ko, es, pt-BR, fr, de, ar, hi and id.

Edit `catalog.json`, then run `python3 scripts/build-localizations.py`. Commit the catalog and generated `.strings` files together. Run the same script with `--check` to detect missing languages, stale resources and format-argument mismatches. Positional placeholders keep file names and counts in the right order for each language. File-count labels avoid singular/plural ambiguity by using a label followed by a number.

App resources stay in the iOS host. Foundation-only repository errors have their own SwiftPM resource bundle. SwiftPM may lowercase compound locale directory names, so error lookup matches locale codes case-insensitively. No UI or credential dependency is added to VaultCore.

`L10n` localizes app chrome, never repository paths, titles, text or tokens. The shared renderer receives only a language tag and five translated UI labels through an additive reader-v2 method. It defaults to English for hosts that omit that call. Metadata chrome follows the UI direction; prose detects its own direction, while code stays left-to-right. Offline Noto Arabic and Devanagari faces supplement the existing CJK font; their script-only ranges preserve Latin prose and monospaced code. Native SwiftUI mirrors its layout for Arabic. Credentials and URLs remain left-to-right where entered.

Synthetic sample documents are English outside Chinese interfaces; Chinese interfaces retain the existing Chinese samples. The full reviewed help and privacy documents remain English/Simplified Chinese, with a localized notice in the other interfaces. User documents always retain their original language. Interface translations were prepared with AI assistance; this does not claim professional native-speaker review or regional keyword-volume validation.
