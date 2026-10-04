# Packaging and installation

Bonk is a local macOS application. Swift Package Manager builds the `Bonk` menu-bar executable and `BonkCore` library, along with the executable checks, XCTest suite, character-gallery renderer, and app-icon builder defined in [Package.swift](../Package.swift).

## Toolchain and verification

Use macOS 13 or newer and Swift 5.10 or newer. Build, executable checks, packaging, and installation work with the standalone Command Line Tools. Full Xcode 15.4 or newer is required for the XCTest suite; select it with `xcode-select` before running `make verify`.

Commands run from the repository root:

| Command | Result |
| --- | --- |
| `make install` | Resolves Swift package dependencies. |
| `make build` | Builds with compiler warnings treated as errors. |
| `make check` | Runs the `BonkChecks` executable. |
| `make validate` | Runs the build and executable checks. |
| `make verify` | Adds the XCTest suite to validation. |
| `make app` | Validates, packages, and verifies `dist/Bonk.app`. |
| `make run` | Builds the bundle and launches it from `dist/`. |
| `make export` | Builds and installs the bundle into Applications. |
| `make screenshots` | Regenerates the character gallery and Guard Mode preview. |
| `make clean` | Cleans Swift build output and removes `dist/Bonk.app`. |

Run `make` or `make help` for target descriptions. CI runs `make verify app` on macOS.

## App bundle

[Scripts/build-app.sh](../Scripts/build-app.sh) is the source of truth for packaging. It builds in release mode, assembles `dist/Bonk.app`, copies the executable and [Info.plist](../Packaging/Info.plist), generates `AppIcon.icns`, and embeds `Bonk_BonkCore.bundle` under `Contents/Resources`. It checks the plist and ad-hoc signs the complete app. The `make app` target then verifies that signature with `codesign --verify --deep --strict`.

The script accepts `BONK_SDK_PATH` for a custom SDK and `BONK_CACHE_PATH` for a custom Swift build-cache location. Setting a custom SDK also passes `--disable-sandbox` to the Swift build. Normal builds require neither override.

The generated bundle uses ad-hoc signing. No distribution signing or notarization step is part of the current packaging workflow.

## Install and launch

```sh
make export
```

The [Makefile](../Makefile) installs into `/Applications` when writable, otherwise `~/Applications`. It replaces an existing `Bonk.app` at the destination and verifies the copied signature. The build remains available at `dist/Bonk.app`.

To choose a destination:

```sh
make export INSTALL_DIR="$HOME/Applications"
```

Launch Bonk through Spotlight or Applications. Grant Accessibility permission under **System Settings → Privacy & Security → Accessibility**; after a rebuild, disable and re-enable the entry if macOS retains an earlier build's permission. See [Getting started](getting-started.md) for activation, owner authentication, and optional Jev credentials.
