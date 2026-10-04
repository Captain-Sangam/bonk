# Bonk documentation

These documents describe Bonk's implemented behavior, architecture, and safety boundaries.

- [Getting started](getting-started.md) — requirements, permissions, activation, unlock, and optional Jev setup
- [Features and character behavior](features.md) — capabilities, reaction gallery, and use cases
- [Architecture](architecture.md) — components, state transitions, cursor/reaction separation, and cleanup
- [Packaging and installation](packaging.md) — toolchains, Make targets, app-bundle contents, signing, and installation
- [Contributor guide](contributing.md) — workflow, safety invariants, and character, dialogue, and asset guidance
- [Interaction design](interaction-design.md) — instant cursor tracking, typing energy, Jev-directed reactions, and double-Escape unlock
- [Reaction engine](reaction-engine.md) — on-device responses, readability and rest, optional Jev direction, and validation
- [Privacy and security](privacy-and-security.md) — trust boundaries, collected data, and failure behavior
- [Character generation prompts](design/character-prompts.md) — reproducible art direction for the original fox mascot

The screenshots in [`images/`](images/) are generated or source-controlled project assets. Regenerate the runtime previews from the repository root with:

```sh
make screenshots
```

For a quick contribution checklist, see [CONTRIBUTING.md](../CONTRIBUTING.md). Bonk uses the [MIT License](../LICENSE).
