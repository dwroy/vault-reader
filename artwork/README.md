# Vault Reader identity

Original vector artwork: two open pages forming a V, with a bookmark. The green matches the native reader accent. These paths are authored for this project, not derived from SF Symbols.

- `logo.svg`: transparent standalone mark; native wordmark uses Dynamic Type text.
- `app-icon.svg`: full square icon master; iOS applies its own corner mask.
- `VaultReader/Assets.xcassets`: opaque 1024 px default, dark and grayscale tinted icons; vector PDF logos for light/dark UI.

Regenerate all exports from the shared path definitions, from the repository root on macOS:

```sh
swift scripts/generate-brand-assets.swift
```

No third-party tools or fonts are needed. XcodeGen selects `AppIcon` through `project.yml`; the renderer and credential storage are unaffected.
