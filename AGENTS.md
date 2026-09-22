# Vault Reader development

- Product: native read-only vault reader; iOS first, Android second. Current scope is M1b; M2/M3 remain out of scope. Follow `docs/ARCHITECTURE.md` and record acceptance limits honestly in `docs/ACCEPTANCE.md`.
- Keep feature work in the project root's `.worktrees/<task>/`. Main checkout is for integration and final builds. Do not push without explicit authorization.
- Shared rendering lives in `packages/reader-web`; do not add WebKit/Android APIs there. Adapt hosts through `packages/contracts/reader-v1.d.ts`. Credentials never cross that bridge.
- `packages/VaultCore` has no UI or Keychain dependencies. Swift 6, zero third-party Swift libraries. Android native data adapters are future work; this package is not a promise of Android code sharing.
- Use XcodeGen `project.yml`; generated `.xcodeproj` is ignored. After JS/CSS changes run `npm run build:renderer` and commit source, generated bundle and license notices together.
- Relevant checks: `npm test`, `swift test --package-path packages/VaultCore`, Xcode simulator tests, and `node tests/resolve-links.mjs /path/to/vault --summary` when changing link resolution.
- Real vault contents, link reports, screenshots and credentials must stay out of git. Store local evidence under ignored `build/`. Demo fixtures must be synthetic.
- Use the personal Apple developer team for device builds. Do not select the company team or add a guessed team ID.
