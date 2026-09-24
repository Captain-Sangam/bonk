# Privacy and security

Bonk is an input guard, not a replacement for the macOS Lock Screen. The desktop remains visible by design, so use the system lock screen when confidentiality against a nearby observer matters.

## Local trust boundary

Input suppression, overlays, the double-Escape detector, device-owner authentication, keep-awake behavior, and cleanup are local. Bonk does not record keystrokes, inspect application content, read the clipboard, or capture the screen.

The event interceptor observes enough metadata to classify an attempted action. Escape key-code recognition is isolated to the local unlock detector; raw key codes and typed content do not enter the reaction pipeline.

## Optional network boundary

Jev reactions are opt-in. When enabled, Bonk sends only the aggregated snapshot documented in [Reaction engine](reaction-engine.md). The TypeSafe API key is stored in the macOS Keychain and used only as an authorization header. Bonk does not persist Jev payloads or responses beyond the active session.

Guard Mode remains fully functional with networking disabled.

## Failure behavior

Bonk fails open when a safety-critical component cannot continue. Cleanup stops input interception, releases the power assertion, removes every overlay, and cancels pending reaction work.

An authentication rejection or user cancellation is recoverable and returns to Guard Mode. If interception or overlay protection cannot be restored, Bonk ends the session rather than risk trapping the owner.

## Responsible disclosure

Please do not publish exploitable security details in a normal issue. Follow the private reporting guidance in [`SECURITY.md`](../SECURITY.md).
