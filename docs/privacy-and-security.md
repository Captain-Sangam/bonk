# Privacy and security

Bonk is an input guard, not a replacement for the macOS Lock Screen. In the classic fox mode the desktop stays visible by design, so use the system lock screen when confidentiality against a nearby observer matters. The screen-off and agents away-screen modes cover every display with an opaque screen, but they still do not encrypt the session or substitute for the macOS Lock Screen.

## Local trust boundary

Input suppression, overlays, the double-Escape detector, device-owner authentication, keep-awake behavior, and cleanup are local. Bonk does not record keystrokes, inspect application content, read the clipboard, or capture the screen.

The event interceptor observes enough metadata to classify an attempted action. Escape key-code recognition is isolated to the local unlock detector; raw key codes and typed content do not enter the reaction pipeline. Typing growth uses only local, non-repeat key timestamps in a rolling window.

## Intrusion camera

The intrusion camera is opt-in and off by default. When you enable it in Settings, Bonk requests camera access there (while idle), so the system prompt never appears beneath the guard overlay. With it enabled, Bonk takes a single still **only** when an unlock attempt is genuinely rejected — a wrong password or biometric. Dismissing the prompt ("Keep Bonk On"), a system cancellation, or a successful unlock never takes a photo.

Photos are written only to `~/Pictures/Bonk/` on your Mac and are never uploaded; delete them from that folder at any time. After you unlock, the menu notes how many attempts were captured and reveals the folder. Capture runs off the main thread and is fire-and-forget, so it can neither delay unlocking nor keep the input guard from releasing.

## Agent scanning

The agents away-screen lists the processes still running so you can see what is working while you are away. It does this locally by matching running-process names (via `ps`) against the comma-separated list you configure in Settings. No process list, command line, or environment is sent anywhere; only matching names are shown on your own screens.

## Optional network boundary

Jev direction is opt-in. When enabled, Bonk waits for a two-second quiet period and sends only the aggregated snapshot documented in [Reaction engine](reaction-engine.md), plus bounded reaction criteria and a shortlist of curated dialogue IDs and text. The shortlist is authored inside Bonk and never contains user input.

The TypeSafe API key is stored in the macOS Keychain and used only as an authorization header. Bonk does not persist Jev payloads, decisions, exact pointer positions, or session histories beyond the active guarded session. Settings may display the latest bounded decision labels while that session is active.

Guard Mode remains fully functional with networking disabled.

## Failure behavior

Bonk fails open when a safety-critical component cannot continue. Cleanup stops input interception, releases the power assertion, removes every overlay, and cancels pending reaction work.

An authentication rejection or user cancellation is recoverable and returns to Guard Mode. If interception or overlay protection cannot be restored, Bonk ends the session rather than risk trapping the owner.

## Responsible disclosure

Please do not publish exploitable security details in a normal issue. Follow the private reporting guidance in [`SECURITY.md`](../SECURITY.md).
