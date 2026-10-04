# Features and character behavior

Bonk keeps the desktop visible and the Mac awake while blocking unwanted keyboard, mouse, and trackpad input. It is useful for dashboards, demos, long-running tasks, keyboard cleaning, curious pets, and any moment when the screen should stay on but hands should stay off.

Bonk is not a replacement for the macOS Lock Screen. Anything already visible remains visible. Bonk is early-stage software; review the code and understand its Accessibility permission before relying on it.

## Highlights

- Native SwiftUI and AppKit menu-bar app with no game engine or web runtime
- Accessibility-backed global input suppression with fail-open cleanup
- Transparent protection across every connected display
- Instant 120 Hz local virtual-cursor tracking, independent of network decisions
- Typing-speed energy that grows the fox up to a safe visual limit, then counts down smoothly
- On-device responses shaped by movement gestures and typing pace
- Four-second reading windows and a resting fox after 20 seconds of inactivity
- Optional Jev direction for reaction, tone, pacing, flourish, intensity, and dialogue selection
- More than 600 curated dialogue options with context filtering and anti-repetition
- Double Escape as the only guarded-input path to macOS owner authentication
- Two-second Jev quiet-period scheduling to avoid jitter during input bursts
- Strict schema, allowlist, confidence, freshness, and bounds validation around every Jev result
- Complete deterministic offline reaction engine
- Keychain storage for the optional Jev API key
- Reproducible character assets and screenshot tooling

## Character reactions

![Bonk's sixteen reaction states](images/reaction-gallery.png)

Mouse movement, clicks, scrolling, typing, and shortcut attempts produce different poses and motion. The virtual cursor follows movement immediately. While a message is within its four-second reading window, the fox stays in place so the bubble remains readable. Clicks and keys change its pose immediately while text waits; movement and scrolling respect the current reaction window. After 20 seconds without input, the fox rests and hides its bubble; the next input wakes it. Faster typing charges the fox from `1.0×` up to `1.65×`; after typing stops, it eases back to normal over four seconds.

Input attempts never open Touch ID. To unlock, press `Esc` twice within 650 milliseconds; holding the key does not count.
