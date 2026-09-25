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
make verify
```

Build the app bundle with:

```sh
make run
```

Grant Accessibility permission only to a locally built binary you trust. macOS may require you to toggle the permission after rebuilding.

Useful targets are `make validate` for build-time checks, `make verify` to include the XCTest suite, `make app` for a signed bundle, `make run` to build and launch, and `make screenshots` to regenerate the checked-in character previews. Full Xcode is required only for `make verify`.

## Pull requests

Keep pull requests narrow and explain the user-visible behavior. Include tests for logic changes and screenshots for visible changes. Before submitting, run:

```sh
make verify app
```

Use clear commit messages and do not commit `.build/`, `dist/`, credentials, developer signing identities, or local Xcode state.

## Safety invariants

Changes must preserve these rules:

- A failure in interception or overlays ends Guard Mode and restores normal input.
- Only the local double-Escape gesture starts owner authentication while guarded.
- Jev and network access never control interception, authentication, or cleanup.
- Typed content, raw key codes, exact cursor paths, screen contents, and application context never leave the Mac.
- Exact virtual-cursor updates remain local, immediate, and independent of Jev.
- Jev requests remain quiet-period debounced, cancellable, session-scoped, confidence-gated, and allowlisted.
- Dialogue shown by the app comes from the curated catalogue; Jev selects bounded IDs and never generates arbitrary text.
- Authentication remains owned by macOS `LocalAuthentication`.
- Every connected display remains protected for the full guarded session.

## Character and asset contributions

Keep Bonk original and readable at small sizes. Do not submit copied characters, costumes, logos, franchise insignia, or assets without redistribution rights. If generated tools assisted the work, include reproducible prompts and identify the workflow in `docs/design/`.

Runtime character changes should update the gallery when relevant:

```sh
make screenshots
```

Dialogue contributions belong in `DialogueCatalog.swift`. Keep every line short enough for the overlay, preserve a clear double-Escape instruction for unlock hints, and add variety without insults, sensitive inferences, or references to typed content. Changes to the Jev question contract should update `docs/reaction-engine.md` and include request/response validation tests.
