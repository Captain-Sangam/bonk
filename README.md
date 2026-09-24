# Bonk

Bonk is a playful native macOS menu-bar input guard. It keeps the Mac awake and the desktop visible, intercepts keyboard and pointing-device input, reacts with a tiny character, and restores control after macOS device-owner authentication.

Bonk is not a replacement for the macOS Lock Screen. Anything visible before Guard Mode remains visible.

## Current MVP

- Menu-bar activation and configurable `⇧⌘B` shortcut
- Accessibility-backed `CGEventTap` input interception
- Fail-open cleanup if interception, overlays, permissions, or authentication fail
- Transparent AppKit overlay on every connected display
- Native `LocalAuthentication` Touch ID/password flow
- Sleep prevention while Guard Mode is active
- Custom vector cat with gaze tracking, animated gait, props, and expressive state-specific poses
- Speed- and direction-aware pointer tracking with pounce, stalk, bonk, swat, cling, tumble, and typing reactions
- Optional TypeSafe AI Jev reaction selection with strict typed validation
- Immediate deterministic local reactions and complete offline fallback
- First-launch privacy and permission onboarding
- Local settings, Keychain API-key storage, and launch-at-login support

The detailed product and safety requirements live in [spec.md](spec.md).

## Requirements

- macOS 13 or newer
- Swift 5.10 or newer
- Xcode 15.4 or newer for the XCTest suite and normal app development
- Accessibility permission to suppress global input
- Touch ID or another device-owner authentication method supported by macOS

## Build and test

```sh
swift build
swift test
swift run BonkChecks
swift run BonkCharacterGallery /tmp/bonk-character-gallery.png
```

Build an ad-hoc signed `.app` bundle:

```sh
Scripts/build-app.sh
open dist/Bonk.app
```

The first launch asks for Accessibility access. If macOS does not refresh the permission automatically, disable and re-enable Bonk under **System Settings → Privacy & Security → Accessibility**.

## Jev reactions

AI reactions are opt-in. Add a TypeSafe API key in Bonk Settings or set `TYPESAFE_API_KEY` for a development launch. The key is stored in the macOS Keychain when entered in Settings and is sent only as an authorization header.

Jev receives a compact JSON snapshot containing categories and aggregates such as `rapidClick`, recent counts, a motion-energy bucket, coarse direction, and a coarse cursor region. Precise pointer coordinates and paths stay local so they can drive fluid animation without leaving the Mac. Bonk never sends typed characters, key codes, screen contents, window titles, clipboard contents, filenames, URLs, or precise cursor history.

Jev is outside the safety-critical path. Input interception, authentication, cleanup, and offline reactions do not depend on the network or model.

## Architecture

`GuardController` owns the guarded-session lifecycle. Its cleanup path always stops the event tap, releases the power assertion, removes overlays, and cancels reaction work. `ReactionController` shows a local reaction immediately, coalesces bursts, and optionally replaces the presentation with a validated Jev choice. Authentication temporarily stops the event tap so the macOS password fallback can receive input while the overlay continues to cover ordinary applications.

The repository is intentionally a Swift Package so it can build from the command line and be opened directly in Xcode.
