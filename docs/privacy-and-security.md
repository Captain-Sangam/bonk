# Privacy and security

Bonk is an input guard, not a replacement for the macOS Lock Screen. The desktop remains visible by design, so use the system lock screen when confidentiality against a nearby observer matters.

## Local trust boundary

Input suppression, overlays, the double-Escape detector, device-owner authentication, keep-awake behavior, and cleanup are local. Bonk does not record keystrokes, inspect application content, read the clipboard, or capture the screen.

The event interceptor observes enough metadata to classify an attempted action. Escape key-code recognition is isolated to the local unlock detector; raw key codes and typed content do not enter the reaction pipeline. Typing growth uses only local, non-repeat key timestamps in a rolling window.

## Optional network boundary

Jev direction is opt-in. When enabled, Bonk waits for a two-second quiet period and sends only the aggregated snapshot documented in [Reaction engine](reaction-engine.md), plus bounded reaction criteria and a shortlist of curated dialogue IDs and text. The shortlist is authored inside Bonk and never contains user input.

The TypeSafe API key is stored in the macOS Keychain and used only as an authorization header. Bonk does not persist Jev payloads, decisions, exact pointer positions, or session histories beyond the active guarded session. Settings may display the latest bounded decision labels while that session is active.

Guard Mode remains fully functional with networking disabled.

## Failure behavior

Bonk fails open when a safety-critical component cannot continue. Cleanup stops input interception, releases the power assertion, removes every overlay, and cancels pending reaction work.

An authentication rejection or user cancellation is recoverable and returns to Guard Mode. If interception or overlay protection cannot be restored, Bonk ends the session rather than risk trapping the owner.

## Responsible disclosure

Please do not publish exploitable security details in a normal issue. Follow the private reporting guidance in [`SECURITY.md`](../SECURITY.md).
