# Contributing to Bonk

Thanks for helping improve Bonk. Contributions should preserve its two defining qualities: input guarding must be dependable, and the character should make that dependable behavior delightful.

## Before you start

- For bugs or small improvements, open an issue or a focused pull request.
- For large behavior changes, propose the design first so safety and interaction tradeoffs are visible before implementation.
- For vulnerabilities, follow [`SECURITY.md`](SECURITY.md) instead of opening a public issue.

## Development setup

You need macOS 13 or newer, Swift 5.10 or newer, and Xcode 15.4 or newer.

```sh
git clone https://github.com/Captain-Sangam/bonk.git
cd bonk
swift build
swift test
swift run BonkChecks
```

Build the app bundle with:

```sh
Scripts/build-app.sh
open dist/Bonk.app
```

Grant Accessibility permission only to a locally built binary you trust. macOS may require you to toggle the permission after rebuilding.

## Pull requests

Keep pull requests narrow and explain the user-visible behavior. Include tests for logic changes and screenshots for visible changes. Before submitting, run:

```sh
swift build -Xswiftc -warnings-as-errors
swift test
swift run BonkChecks
Scripts/build-app.sh
codesign --verify --deep --strict dist/Bonk.app
```

Use clear commit messages and do not commit `.build/`, `dist/`, credentials, developer signing identities, or local Xcode state.

## Safety invariants

Changes must preserve these rules:

- A failure in interception or overlays ends Guard Mode and restores normal input.
- Only the local double-Escape gesture starts owner authentication while guarded.
- Jev and network access never control interception, authentication, or cleanup.
- Typed content, raw key codes, exact cursor paths, screen contents, and application context never leave the Mac.
- Authentication remains owned by macOS `LocalAuthentication`.
- Every connected display remains protected for the full guarded session.

## Character and asset contributions

Keep Bonk original and readable at small sizes. Do not submit copied characters, costumes, logos, franchise insignia, or assets without redistribution rights. If generated tools assisted the work, include reproducible prompts and identify the workflow in `docs/design/`.

Runtime character changes should update the gallery when relevant:

```sh
swift run BonkCharacterGallery \
  docs/images/reaction-gallery.png \
  docs/images/guard-mode-preview.png
```
