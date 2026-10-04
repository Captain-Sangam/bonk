# Contributing to Bonk

Open a focused issue or pull request for bugs and small improvements. Propose larger behavior changes first, and report vulnerabilities using [SECURITY.md](SECURITY.md).

## Setup and verification

Use macOS 13+, Swift 5.10+, and Xcode 15.4+ for contributor verification:

```sh
git clone https://github.com/Captain-Sangam/bonk.git
cd bonk
make verify app
```

Use `make run` to build and launch locally. Grant Accessibility permission only to a build you trust; macOS may require toggling the permission after a rebuild.

## Pull requests

Keep changes focused, explain the user-visible behavior, and list the checks you ran in the pull request. Include tests for logic changes and screenshots for visible changes. Do not commit build output, credentials, signing identities, or local Xcode state.

Read the [contributor guide](docs/contributing.md) for safety invariants, development targets, and character, dialogue, and asset guidelines. See [Architecture](docs/architecture.md) and [Packaging and installation](docs/packaging.md) for implementation context.
