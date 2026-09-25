# Bonk documentation

These documents capture Bonk's current logical design. They describe the behavior and safety boundaries implemented by the code rather than a future product backlog.

- [Architecture](architecture.md) — components, ownership, cursor/reaction separation, state transitions, and cleanup
- [Interaction design](interaction-design.md) — instant cursor tracking, typing energy, Jev-directed reactions, and double-Escape unlock
- [Reaction engine](reaction-engine.md) — Jev's core directing role, quiet-period scheduling, dialogue selection, and validation
- [Privacy and security](privacy-and-security.md) — trust boundaries, collected data, and failure behavior
- [Character generation prompts](design/character-prompts.md) — reproducible art direction for the original fox mascot

The screenshots in [`images/`](images/) are generated or source-controlled project assets. Regenerate the runtime previews with:

```sh
swift run BonkCharacterGallery \
  docs/images/reaction-gallery.png \
  docs/images/guard-mode-preview.png
```
