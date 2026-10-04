<p align="center">
  <img src="Sources/BonkCore/Resources/bonk-app-icon.png" width="144" alt="Bonk fox app icon">
</p>

<h1 align="center">Bonk</h1>

<p align="center"><strong>A playful macOS input guard with an on-device fox personality.</strong></p>

Keep your desktop visible and your Mac awake while a tiny fox blocks unwanted keyboard, mouse, and trackpad input. Reactions run locally; Jev adds optional creative direction.

> [!IMPORTANT]
> Bonk is not a replacement for the macOS Lock Screen. Anything already visible remains visible.

![Bonk guarding a visible desktop](docs/images/guard-mode-preview.png)

![Bonk's sixteen reaction states](docs/images/reaction-gallery.png)

## Build and install

Requires macOS 13+ and Swift 5.10+. The standalone Command Line Tools support building and packaging; full Xcode 15.4+ is needed for the XCTest suite.

```sh
git clone https://github.com/Captain-Sangam/bonk.git
cd bonk
make export
```

Launch **Bonk** from Spotlight or Applications and grant Accessibility permission in **System Settings → Privacy & Security → Accessibility**. Activate it from the menu-bar paw or `⇧⌘B`; press `Esc` twice to start macOS owner authentication and unlock.

`make export` validates, packages, and installs the app into `/Applications` or `~/Applications`. Use `make run` to build and launch from `dist/`, or `make app` to package only. See [Getting started](docs/getting-started.md) for permissions, unlock timing, and optional Jev setup.

## Documentation and contributions

- [Documentation index](docs/README.md)
- [Features and character behavior](docs/features.md)
- [Architecture](docs/architecture.md)
- [Packaging and installation](docs/packaging.md)
- [Contributing](CONTRIBUTING.md) and [security reporting](SECURITY.md)

Bonk is available under the [MIT License](LICENSE).
