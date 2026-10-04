# Getting started

## Requirements

- macOS 13 or newer
- Swift 5.10 or newer
- Xcode 15.4 or newer only for the XCTest suite and contributor verification
- Accessibility permission to suppress global input
- Touch ID or another device-owner method supported by macOS

## Build and install

```sh
git clone https://github.com/Captain-Sangam/bonk.git
cd bonk
make export
```

Launch **Bonk** from Spotlight or Applications. The app is installed into `/Applications`, or `~/Applications` if needed. The built app also remains in `dist/Bonk.app` and is ad-hoc signed.

Use `make run` to build and launch directly from `dist/` without installing, or `make app` to package without launching. These commands work with the standalone Command Line Tools; contributors can use `make verify` with full Xcode to include the XCTest suite. Run `make` or `make help` to see all available commands. See [Packaging and installation](packaging.md) for build outputs and custom installation destinations.

## Activate and unlock

On first launch, grant Bonk access under **System Settings → Privacy & Security → Accessibility**. If macOS retains permission for an earlier build, disable and re-enable the entry.

Activate Bonk from the menu-bar paw with **Bonk this Mac** or the configured `⇧⌘B` shortcut. To unlock, press `Esc` twice within 650 milliseconds; holding the key does not count. macOS then handles owner authentication.

## Jev reaction engine

Jev is an optional personality and choreography add-on to Bonk's local reaction engine. With Jev enabled, after input has been quiet for two seconds, Jev directs the next beat across six dimensions in one structured decision: reaction, tone, intensity, pacing, flourish, and dialogue.

Jev results obey the same reading window as local dialogue and are discarded when stale or while the fox is resting. The dialogue library contains 636 curated lines. Bonk narrows those to at most 32 context-relevant candidates before asking Jev to choose, validates that the answer matches the selected reaction, and avoids recently used lines. A Jev Director panel in Settings shows whether the engine is waiting, deciding, applied, or using its local fallback.

Network-powered direction is opt-in because it requires a TypeSafe API key. Enable it and add a key in Bonk Settings, or set `TYPESAFE_API_KEY` for a development launch. Settings confirms the saved credential with a masked suffix; the complete value remains in the macOS Keychain.

Jev receives only coarse, aggregated interaction metadata. It never receives typed content, raw key codes, exact pointer coordinates, screen contents, application context, clipboard data, filenames, or URLs. Jev directs presentation only—it cannot control input interception, authentication, or cleanup. Without a key or network connection, the complete deterministic local reaction engine remains active.

For the decision contract, timing, and validation rules, see [Reaction engine](reaction-engine.md). For trust boundaries and failure behavior, see [Privacy and security](privacy-and-security.md).
