# Plan: block trackpad gestures, fix the shortcut, clean up Settings

## Outcome

While Bonk is guarding, any trackpad gesture can still switch Spaces or open Mission Control, so someone can see other windows by swiping again and again. Bonk's event tap drops only the event types in its mask, and the mask holds no gesture types. The fix adds three raw event types to the same tap:

- **29:** gesture
- **30:** Dock control
- **31:** fluid touch gesture

A probe on this Mac showed every system trackpad gesture reaches a session-level tap as one of these three.

During owner authentication, the tap is no longer stopped. It switches to a pass-through mode. Ordinary input reaches the macOS unlock sheet as today, and gestures stay blocked. If macOS disables the tap in that window, Bonk turns it back on instead of ending Guard Mode, because ending Guard Mode there would unlock the Mac without authentication.

**The shortcut.** It moves from passive `NSEvent` key monitors to a Carbon hotkey (`RegisterEventHotKey`).
- The old monitors depend on Accessibility trust and let the key reach the front app too. A Carbon hotkey needs no permission and consumes the key.
- The owner can record any shortcut that includes ⌘ or ⌃.
- An existing custom letter carries over as ⇧⌘ plus that letter.

**Settings.**
- The window loses its outer padding, so the form scrolls to the window edge.
- The shortcut row becomes a recorder.
- The Jev key area shows either the saved key or an entry field, never both.

**What still needs a person.** Whether dropping these event types actually stops the Dock can only be confirmed by hand on the built app, so that check is the release gate.

## Current behaviour

Inspected at `main` @ `ac3db42c4fa72b176e4bd027129f92b149778c15` in `/Users/zeus/code/bonk`.

### Input tap

- `InputInterceptor` creates one active tap at `.cgSessionEventTap`, inserted at the head (`Sources/BonkCore/InputInterceptor.swift:52-59`).
- `start` also seeds a virtual cursor from the real one (`:68`). `stop` clears the cursor, the pending movement deltas and the double-Escape detector (`:73-93`).
- `handle` updates the virtual cursor, feeds the Escape detector and emits reaction signals (`:104-197`), then returns `nil`, which drops the event (`:199`).
- The mask (`:233-248`) holds mouse buttons, moves, drags, scroll, `keyDown`, `keyUp` and `flagsChanged`. It holds no gesture types.
- A tap-disabled event (`:95-101`) or the 1-second watchdog (`:221-231`) sets `isRunning = false` and reports `eventTapDisabled`. `GuardController.failOpen` then cleans up and goes idle (`GuardController.swift:178-184`, `:186-193`).

### Gesture evidence

`debate/probe-gestures.md` in this task folder records the probe. On macOS 26.6.2, a listen-only session tap saw these for the full gesture set:

- **Raw type 29:** subtypes 0 and 6.
- **Raw type 30:** with the DockSwipe subtype (23).
- **Raw type 31:** with the FluidTouchGesture subtype (27).

It saw none of 18–20, 28 or 32–34. Those numbers are AppKit-only meanings that do not arrive at the tap.

### Authentication

- After double-Escape, `beginOwnerAuthentication` stops the tap (`GuardController.swift:128`). Then it makes the overlay capture input at `.floating` level so the macOS sheet can appear above it (`:129`, `OverlayManager.swift:126-136`). There is a short moment between the two calls where nothing blocks input.
- While the sheet is up, nothing blocks gestures.
- On a failed or cancelled attempt, `resumeAfterAuthenticationFailure` releases the overlay capture first and then restarts the tap (`GuardController.swift:167-176`). That leaves another moment where nothing blocks input.
- On success, cleanup stops everything (`:157-165`).
- `testRealReactionPacingAndRestSurviveAuthenticationFailure` expects `input.startCount == 2` after a failed attempt (`Tests/BonkCoreTests/GuardControllerTests.swift:125`).
- Two fakes conform to `InputIntercepting`:
  - `FakeInputInterceptor` (`GuardControllerTests.swift:249-268`)
  - `PolishInput` (`Checks/PolishChecks.swift:323-330`)

### Overlays

- There is one window per display, with `.canJoinAllSpaces` and `.stationary` (`OverlayManager.swift:118`).
- Classic mode is transparent. Screen off and Agents are opaque (`:80-85`).
- Bonk is an accessory app (`BonkApp.swift:30`) and sets no presentation options.

### Shortcut

- `ShortcutMonitor` installs a global and a local `NSEvent` `keyDown` monitor (`ShortcutMonitor.swift:18-30`).
- It matches when ⇧⌘ is among the flags, so extra modifiers also match. It also requires `charactersIgnoringModifiers` to equal the stored letter (`:50-56`).
- `SettingsStore.shortcutKey` holds one letter, default `"B"` (`SettingsStore.swift:25-27`, `:66`, `:123`).
- `SettingsStore.lastError` is `private(set)` (`:54`).
- Callers of `shortcutKey`:
  - `AppModel.swift:52`, `:54`
  - `SettingsView.swift:172-175`
  - `BonkApp.swift:250`
- `AppModel` installs the monitor at launch and again when the letter changes (`AppModel.swift:49-64`, `:78-82`).
- `toggleGuard` only activates, and it does nothing while guarding (`:67-70`, `Models.swift:10`).
- The menu item mirrors ⇧⌘ plus the letter (`BonkApp.swift:185`, `:249-251`).

**Why it fails today.** The exact cause is not proven. Several weaknesses each explain it:
- The monitor depends on Accessibility trust, and ad-hoc rebuilds can leave that trust stale (`Scripts/build-app.sh:41`, `docs/getting-started.md:25`).
- The monitor is passive, so the front app receives the key too.
- The monitor sees nothing under secure input (from memory).

### Settings

- The window is created at 480×500 (`BonkApp.swift:89`, in `SettingsWindowController.show`, `:76-101`).
- The view applies `.formStyle(.grouped)`, then `.padding()`, then `.frame(width: 500, height: 640)` (`SettingsView.swift:186-188`). The padding sits outside the form, so the form's scroll bar is inset from the window edge, and the two sizes disagree.
- The shortcut row shows `Text("⇧⌘")` and `TextField("B", …)`. The field's title renders as a label, so the row reads "⇧⌘ B B" (`:167-178`).
- The Jev section has all of these at once (`:83-139`):
  - a toggle
  - a "Jev API key" headline
  - a green status card
  - `SecureField("Paste TypeSafe API key")`
  - Save Key and Remove buttons
  - a privacy caption
- Jev calls TypeSafe's API (`ReactionEngine.swift:244`), and the stored key is a TypeSafe key (`SettingsStore.swift:7`, `:73-83`).

### Docs

`⇧⌘B` is named as the activation shortcut in `README.md:28`, `docs/getting-started.md:27` and `docs/interaction-design.md:7`. `docs/interaction-design.md:27` is a different row: it says what happens when someone tries a shortcut while Bonk is guarding.

## Decisions

| # | Decision | Why | Strongest rejected alternative |
|---|---|---|---|
| 1 | Add raw event types 29, 30 and 31 to the existing tap's mask. `handle` drops them. | The probe shows every system trackpad gesture reaches a session tap as one of these types. The Dock is an ordinary receiver after the session tap, so dropping them at the head of that tap should stop each gesture before any window moves. The probe proves the events arrive, not that dropping them works, so a manual check on the built app is the release gate. The same tap means the same fail-open path. | `NSApplication.presentationOptions` kiosk flags. They apply only while Bonk is the active app. An accessory app can lose activation silently, and gestures would then work again without failing open. Also rejected: adding 18–20, 28 or 32–34, which were not observed at the tap. |
| 2 | During authentication, the tap keeps running in a pass-through mode. Every non-gesture event passes unchanged, with no reaction signal, no virtual-cursor update and no Escape detection. Gestures are still dropped. Order of operations: on entry, capture the overlay first, then turn pass-through on. On a failed attempt, turn pass-through off first, then release the overlay. | Today nothing blocks gestures while the unlock sheet is up, and both hand-offs leave a moment where nothing blocks input. One flag on one tap closes both gaps and keeps a single lifecycle. | A second gesture-only tap that runs for the whole session. It gives the same coverage, but with a second lifecycle, a second failure path and more code. No failure was found that it avoids and pass-through does not. |
| 3 | While pass-through is on, a disabled tap (a tap-disabled event or the watchdog) is turned back on and reported to no one. When pass-through ends after a failed attempt, the tap must be enabled: turn it on again, recreate it if that does not hold, and if that fails too, fail open. | Fail open exists to restore normal input. In pass-through, input already flows, so ending Guard Mode there would unlock the Mac without `LocalAuthentication`. Today no tap runs during authentication, so this is not possible now, and it must stay that way. If the tap cannot be turned back on, the cost is that gestures go unblocked until the sheet closes, which matches today. | Failing open on any tap failure during authentication. That would add an unlock path that skips authentication, against the rule that authentication stays owned by macOS `LocalAuthentication`. |
| 4 | Replace the `NSEvent` monitors with one Carbon `RegisterEventHotKey` registration, using the `kEventHotKeyExclusive` option, and one `kEventHotKeyPressed` handler. | It needs no permission and consumes the key, so the front app does not also act on it. It matches the physical key and works under secure input (from memory). Exclusive registration fails if another app already holds the combination, so that conflict is caught for free. Carbon ships with the SDK, so there is no new dependency. The decision holds whatever today's exact failure cause is. | Keeping `NSEvent` monitors and re-installing them when trust changes. They stay permission-dependent and passive. |
| 5 | Store the shortcut as a key code, modifier flags and a display label. Migrate an old letter A–Z to ⇧⌘ plus that letter through a fixed `kVK_ANSI_*` table. Anything else becomes ⇧⌘B. | It is the smallest value that drives registration, the recorder label and the menu key equivalent. The old setting could only hold one character. | Layout-aware migration through `UCKeyTranslate`. It is correct on layouts where letters move, such as German QWERTZ (Y and Z) and French AZERTY. It is extra code for a one-time migration that only affects owners who changed the letter, use such a layout, and had a shortcut that did not work. They can record it again. |
| 6 | The recorder accepts a key whose unmodified character is printable (letters, digits, punctuation), with ⌘ or ⌃ among the modifiers. It refuses Escape, bare keys, ⇧-only and ⌥-only combinations, and anything that fails to register. It ignores auto-repeat. While recording, its local key monitor consumes every key, and the hotkey is unregistered. Registration resumes only after the key is released. Escape, or the window losing focus, cancels. | Requiring ⌘ or ⌃ avoids collisions with typing and avoids the ⌥-only hotkeys that macOS 15 and later refuse (from memory). A printable key gives the label and the menu key equivalent from one value. Consuming the key means it never reaches any menu equivalent. Resuming after release stops a held key from starting Bonk while the owner is in Settings. | Scanning enabled system shortcuts (`CopySymbolicHotKeys`) and app menus for conflicts. Deferred: exclusive registration and a re-record cover the practical cases. |
| 7 | `AppModel` owns the hotkey registration and its outcome. A new shortcut is registered first and saved only on success. On failure, the previous shortcut stays registered and saved, and `AppModel` publishes an error that the recorder row shows. A failure at launch shows in the same row. | Registration, the saved value and the display never disagree. `SettingsStore.lastError` cannot be set from outside the store. | Saving first and reverting on failure. That opens a window where the saved value and the registration disagree, including across a relaunch. |
| 8 | The shortcut only starts Bonk. The row is titled "Start Bonk", and the menu item shows the saved shortcut. | Safety rule: only double-Escape leads to unlock. `toggleGuard` already ignores the shortcut while guarding. | None. |
| 9 | The Jev key area has two states. **Saved:** a "TypeSafe API key" row with the masked suffix, Replace… and Remove. **Entry** (no key, or replacing): one secure field with its label hidden, Save as the default action, and Cancel when replacing. A footer says Jev runs on TypeSafe AI, followed by the privacy line. Remove the status card, the "Jev API key" headline and the "Saved" text. The old key stays until a new one is saved. | Today one value has three titles, and the saved state and an empty entry field show at the same time. The key really is a TypeSafe key, and Jev is the feature that uses it. | Keeping the status card and collapsing the field. That still shows two states at once. |
| 10 | Remove the outer `.padding()`. Define the window size once, in the view, and create the window from an `NSHostingController` so the window follows that size. | The padding outside the grouped form insets the scroll bar, and the view and window sizes disagree. | Setting the window's `contentRect` to match the view frame. That puts the same number in two places, where it can drift. |

## Scope and acceptance criteria

**Delivered:**
- Gesture blocking for the whole guarded session, including authentication.
- A Carbon hotkey with a recorder and migration from the old letter.
- The two-state Jev key area.
- The Settings window layout.
- Docs that call the shortcut changeable and say gestures are blocked.

**Excluded:**
- Hot corners and other pointer-driven system features.
- Letting the shortcut stop Bonk.
- Function, arrow and other non-printable keys in the recorder.
- System-shortcut conflict scanning.
- Showing an environment-provided TypeSafe key differently from a saved one. That fallback is for development launches only.
- Signing and packaging.

**Acceptance criteria.** Criteria 1, 2 and 7 involve a person:

1. **Gestures blocked in every mode.** Test Classic, Screen off and Agents on a real Mac with at least two Spaces, plus a second display where one is available. In each mode, none of these gestures changes anything on screen, in three- or four-finger form:
   - Spaces swipe
   - Mission Control
   - App Exposé
   - Launchpad pinch
   - Show Desktop spread
   - Notification Centre edge swipe
2. **Gestures blocked around unlock.** The same gestures change nothing while the authentication sheet is showing, or right after a failed or cancelled unlock.
3. **Failures outside authentication.** If the tap is disabled or fails, Bonk goes idle and normal input returns, as today.
4. **Failures during authentication.**
   - A tap failure while the sheet is showing never ends Guard Mode. Only a successful authentication does.
   - After a failed attempt, if the tap cannot be re-armed, Bonk fails open.
5. **The shortcut fires from anywhere.**
   - The saved shortcut starts activation from any front app, including a browser where ⇧⌘B is also a browser shortcut, and from a password field. The front app does not also act on the key.
   - With a stale Accessibility grant, the shortcut still fires. Activation then asks for Accessibility, exactly as the menu item does.
6. **The shortcut is safe.** It never starts authentication and never stops Bonk.
7. **Recording works.**
   - A recorded shortcut works at once and survives a relaunch.
   - A refused or unregistrable combination leaves the previous shortcut working and saved, and shows why.
   - Holding the new combination while recording does not start Bonk.
8. **Migration.** An existing letter setting X becomes ⇧⌘X on first launch. A missing or invalid value becomes ⇧⌘B.
9. **Window.** The Settings scroll bar sits at the window's right edge, and the window and view sizes match.
10. **Jev area.** It never shows the saved key and an empty entry field at once. The key is labelled as a TypeSafe API key, and one line says Jev runs on TypeSafe AI.

## Implementation plan

### Step 1: gesture types in the tap mask

- **Change.** In `InputInterceptor`, add raw types 29, 30 and 31 to the mask (`InputInterceptor.swift:233-248`). They have no named `CGEventType` case, so build their mask bits from raw values. Give the three values a named constant with a one-line comment that cites the probe. Make the mask readable from tests (internal, not private).
- **Implements.** Decision 1.
- **Invariant.** While the tap is enabled, gesture events never reach the Dock or apps. An unexpected event of these types is dropped, which errs toward blocking. Tap failure still fails open.
- **Verified today.** The mask is at `:233-248`, and every masked event is dropped at `:199`.
- **Depends on.** Nothing.
- **Check.** Proposed test in a new `Tests/BonkCoreTests/InputInterceptorTests.swift`: the mask has bits 29, 30 and 31 set. Run `swift test --filter InputInterceptorTests`. Manual: acceptance criterion 1. Commit.

### Step 2: pass-through during authentication

- **Change.**
  - **Protocol.** Add a settable `allowsOwnerInput` to `InputIntercepting` (`ServiceProtocols.swift:3-11`). Also add it to `InputInterceptor`, `FakeInputInterceptor` (`GuardControllerTests.swift:249-268`) and `PolishInput` (`Checks/PolishChecks.swift:323-330`).
  - **In `handle`.** The tap-disabled check stays first.
    - When `allowsOwnerInput` is true and the tap is disabled, turn it back on, keep `isRunning` true and do not call `onFailure`.
    - Right after that check, when `allowsOwnerInput` is true, return `nil` for types 29–31 and every other event unchanged, before any cursor, signal or Escape code (`:104` onward).
    - The watchdog (`:221-231`) does the same while `allowsOwnerInput` is true: turn the tap back on, report nothing.
  - **Turning pass-through off.**
    - Reset the virtual cursor to the real one, the pending movement deltas, the last-movement time and the Escape detector, as `start` does.
    - Make sure the tap is enabled: turn it on, and if it is still off, stop and start it again. If that fails, report `eventTapDisabled`.
    - `stop()` also sets `allowsOwnerInput` to false.
  - **In `GuardController`.**
    - `beginOwnerAuthentication`: call `overlayManager.setCapturingInput(true)` first, then set `allowsOwnerInput = true`. Do not stop the tap (`:128-129`).
    - `resumeAfterAuthenticationFailure`: set `allowsOwnerInput = false` first, then release the overlay. Drop the tap restart (`:167-176`).
    - If the interceptor is no longer running after that, fail open.
    - Cleanup still calls `stop()`.
- **Implements.** Decisions 2 and 3.
- **Invariant.**
  - Keys, clicks and pointer movement reach the macOS unlock sheet as they do today.
  - From arming until cleanup, either the tap blocks input or the overlay captures it, never neither.
  - While the sheet is up, a tap failure never ends Guard Mode.
  - After a failed attempt, being unable to re-arm the tap fails open.
- **Verified today.** The tap stops at `GuardController.swift:128` before the overlay captures at `:129`. The release-then-restart is at `:167-176`. The fail-open path is at `:178-184`.
- **Depends on.** Step 1.
- **Check.**
  - **Interceptor tests.** Make `handle` internal and test it with synthetic `CGEvent`s:
    - In pass-through, two Escape key-downs pass with no signal and no `onAuthenticationGesture`.
    - A raw type 30 event is dropped in both modes.
    - A tap-disabled event in pass-through does not call `onFailure`, and outside pass-through it does, as today.
  - **Guard tests.**
    - While the fake authentication is pending, the interceptor was not stopped and `allowsOwnerInput` is true.
    - Update the test at `:125`: after a failed attempt, `startCount` stays 1, the interceptor is running and `allowsOwnerInput` is false.
  - **Commands.** `swift test --filter GuardControllerTests`, `swift test --filter InputInterceptorTests`, and `make check` for `PolishInput`.
  - **Manual.** Acceptance criteria 2 and 4. Touch ID, a wrong password and then the right one, and Cancel ("Keep Bonk On") all behave as today.
  - Commit.

### Step 3: shortcut value, migration and Carbon hotkey

- **Change.**
  - **Value.** In `SettingsStore`, replace `shortcutKey` with a small `Shortcut` value: key code, modifier flags and label. Store it under a new defaults key. On init, if that key is absent, map the old `shortcutKey` letter A–Z through a fixed `kVK_ANSI_*` table to ⇧⌘ plus the letter. Anything else becomes ⇧⌘B. Give `Shortcut` a display string (⌃⌥⇧⌘ order, then the label) and a validation function for Decision 6's rules.
  - **Hotkey.** Rewrite `ShortcutMonitor` in the same file around `RegisterEventHotKey` with `kEventHotKeyExclusive` and `UnregisterEventHotKey`. Install one `InstallEventHandler` on the application event target for `kEventHotKeyPressed`. `register(_:)` returns success or the failing `OSStatus`. Add `suspend()` and `resume()` for the recorder.
  - **Registration in `AppModel`.** `AppModel` registers at launch and publishes a shortcut error on failure. Add `setShortcut(_:)`: it registers first, saves on success, and on failure re-registers the previous shortcut and publishes the error (Decision 7). Remove the `$shortcutKey` subscription (`AppModel.swift:52-60`).
  - **Callers.** Update every caller in this step so the build passes:
    - The menu item's `.keyboardShortcut` comes from the saved shortcut (`BonkApp.swift:185`, `:249-251`).
    - The Settings shortcut row temporarily shows the saved shortcut as plain text, titled "Start Bonk" (`SettingsView.swift:167-178`).
- **Implements.** Decisions 4, 5, 7 and 8.
- **Invariant.**
  - A missing or unreadable value always yields ⇧⌘B, never no shortcut.
  - The hotkey only calls `toggleGuard`, which ignores it while guarding.
  - A failed registration affects only the shortcut, never guarding.
- **Verified today.** The cited lines in `SettingsStore`, `ShortcutMonitor`, `AppModel`, `BonkApp` and `SettingsView`.
- **Depends on.** Nothing. It can land before or after Steps 1–2.
- **Check.**
  - **Proposed tests in a new `Tests/BonkCoreTests/ShortcutTests.swift`,** each with a fresh `UserDefaults` suite:
    - Migration: "K" becomes key code 40 with ⇧⌘. A missing value, or "7", becomes ⇧⌘B.
    - Validation refuses a bare letter, ⇧K, ⌥K, ⌥⇧K and ⌘Escape, and accepts ⌘K and ⌃⌥K.
  - **Build.** `make build` treats warnings as errors.
  - **Manual.** Acceptance criteria 5, 6 and 8.
  - Commit.

### Step 4: shortcut recorder

- **Change.**
  - **The row.** Replace the temporary row with `LabeledContent("Start Bonk")` holding a button that shows the shortcut and, when present, the published error beneath it.
  - **Recording.** Clicking the button calls `suspend()` and installs a local monitor for key-down and key-up that returns `nil` for every key.
    - Auto-repeats are ignored.
    - Escape, or the window resigning key, cancels.
    - A valid combination goes to `AppModel.setShortcut`, and an invalid one shows the reason.
    - The monitor is removed and `resume()` is called on key-up, or on cancel, never on key-down.
- **Implements.** Decisions 6, 7 and 8.
- **Invariant.** Recording never starts Bonk. Every way out of the recorder leaves a registered hotkey: the new one, or the previous one.
- **Verified today.** `SettingsView.swift:167-178`.
- **Depends on.** Step 3.
- **Check.** Manual: acceptance criterion 7, including holding the new combination and re-recording the current one. Take a screenshot of the row. Commit.

### Step 5: Jev key area

- **Change.** Rework `SettingsView.swift:83-139` into Decision 9's two states. Keep `saveAPIKey` and `removeAPIKey` as they are; Replace only opens the entry state. Errors from `settings.lastError` show as they do today.
- **Implements.** Decision 9.
- **Invariant.** No change to how the key is stored or how Jev behaves.
- **Verified today.** As cited.
- **Depends on.** Nothing.
- **Check.** Screenshots of the no-key, saved and replacing states against acceptance criterion 10. Commit.

### Step 6: window layout

- **Change.** Remove `.padding()` (`SettingsView.swift:187`) and keep one size in the view, 500×640 as today. In `SettingsWindowController.show` (`BonkApp.swift:76-101`), create the window from an `NSHostingController` so it takes that size.
- **Implements.** Decision 10.
- **Invariant.** The grouped form keeps its native scrolling, which follows the system scroll bar setting.
- **Verified today.** As cited.
- **Depends on.** Nothing.
- **Check.** Screenshots with the scroll bar setting at "Always" and at "When scrolling", against acceptance criterion 9. Commit.

### Step 7: docs

- **Change.**
  - In `README.md:28`, `docs/getting-started.md:27` and `docs/interaction-design.md:7`, describe the shortcut as "your shortcut (default ⇧⌘B), changeable in Settings".
  - In `docs/interaction-design.md`, add one line saying system trackpad gestures are blocked for the whole guarded session, including while the unlock sheet is showing.
  - Leave `docs/interaction-design.md:27` as it is.
- **Implements.** Scope.
- **Depends on.** Steps 1–4.
- **Check.** Read it through. Commit.

## Testing strategy

| Criterion | Check |
|---|---|
| 1, 2 | Step 1 mask test and Step 2 `handle` tests (automated). Manual gesture matrix on the built app (release gate). |
| 3 | The existing `testInputInterceptorFailureImmediatelyFailsOpen` (`GuardControllerTests.swift:30-43`) still passes. |
| 4 | The Step 2 tests for a tap-disabled event during pass-through, and for re-arming after a failed attempt. Manual password checks. |
| 5, 6 | Manual from Safari or Chrome, a password field, after a rebuild, and while guarding. |
| 7 | Manual recorder checks. |
| 8 | `ShortcutTests` migration cases. |
| 9, 10 | Screenshots, which `CONTRIBUTING.md` requires for visible changes. |

- **Commands.** These are from the `Makefile`:
  - `make build`
  - `make check`, which runs `BonkChecks`
  - `swift test`, which needs full Xcode; Xcode is installed on this Mac
  - `make verify app`, which runs build, checks, tests and the signed bundle before a PR
- **Proposed test files:**
  - `Tests/BonkCoreTests/InputInterceptorTests.swift`
  - `Tests/BonkCoreTests/ShortcutTests.swift`
- **Setup.** The manual checks need the built `dist/Bonk.app` with Accessibility granted, a trackpad, at least two Spaces, and a second display if available.

## Constraints and open questions

- **Settled constraints.**
  - No new dependencies.
  - Safety invariants from `docs/contributing.md`. Fail open is kept everywhere except while the unlock sheet is showing, where Decision 3 explains why.
- **Assumption (non-blocking, Steps 1–2).** Dropping types 29–31 at the head of a session tap stops the Dock.
  - The evidence is the probe, plus the Dock receiving these events after the session tap.
  - If the manual check fails, the next candidate is a separate `.cghidEventTap` for these types only. That would need its own measurement and a revised Decision 2.
- **Assumption (non-blocking, Step 3).** These come from memory and are covered by the manual checks:
  - Carbon hotkeys need no permission and fire under secure input.
  - macOS 15 and later refuse ⌥-only hotkeys.
- **Assumption (non-blocking, Step 2).** Whether anyone can trigger `tapDisabledByUserInput` while the unlock sheet is up is unknown. Decision 3 makes it harmless either way.
- **Known limitation (Step 3).** On layouts where letters move, such as QWERTZ or AZERTY, a migrated custom letter can land on a different physical key. The owner records it again.
- **Discretion.** Where the `Shortcut` value lives, the exact Carbon modifier conversion, the label wording in the Jev footer, and the test helper shapes.
- **Readiness.** All steps are ready. Steps 1–2 ship only after the manual gesture check passes.

## For the implementer

- **Before starting.** Confirm `git rev-parse HEAD` is `ac3db42` and that the cited lines still match. If they have moved, re-read each one before editing.
- **Order.** Work in step order. Steps 3, 5 and 6 do not depend on Steps 1–2. End each step with its Check, then commit.
- **As-built notes.** Record deviations in a dated "As built" section at the end of this document.
- **Stop and report if:**
  - gestures still leak in the manual check;
  - Carbon registration asks for any permission;
  - the tap cannot be turned back on during pass-through in practice;
  - an existing test outside the ones named here needs a behavioural change.
- **Resolve alone.** Naming, file placement within `Sources/BonkCore`, SwiftUI layout details within each decision, and the `CGEvent` construction details in tests.

## Verification status

- **Code.** Every reference above was checked in `/Users/zeus/code/bonk` at `ac3db42`.
- **Measured.** The gesture event types were measured on macOS 26.6.2 (build 25G83) with a listen-only probe. Blocking was not measured.
- **From memory.** These are stated as such above:
  - Carbon hotkey behaviour
  - the macOS 15 ⌥-only refusal
  - secure-input behaviour
  - `tapDisabledByUserInput` triggers
- **Unreviewed revision.** Two agents reviewed the draft. Decision 3 (no fail-open while the unlock sheet is showing) came from one agent's plan check and was not checked by the other, who had asked for the opposite test.

## As built (2026-11-11)

### Steps

- **Step 1** `1e87207`: raw types 29, 30, 31 in the tap mask (`InputInterceptor.gestureEventTypes`, internal `eventMask`). `InputInterceptorTests` mask test passes.
- **Step 2** `1ba88bb`: `allowsOwnerInput` pass-through on `InputIntercepting`, the interceptor and both fakes. `GuardController` captures the overlay, then turns pass-through on; on failure it turns pass-through off, releases the overlay, and fails open if the tap is not running. Interceptor and guard tests pass, `make check` passes.
- **Step 3** `97b03ab`: `Shortcut` value with migration and validation, Carbon `ShortcutMonitor`, `AppModel.setShortcut`, menu item and a temporary "Start Bonk" row. `ShortcutTests` pass.
- **Step 4** `aaf4be7`: shortcut recorder in the Settings row. Build passes. Manual check left for the owner.
- **Step 5** `7ca2029`: two-state TypeSafe key area with the TypeSafe AI footer. Build passes. Screenshots left for the owner.
- **Step 6** `e021587`: no outer padding; the window is created from an `NSHostingController`, and the size lives only in the view (500×640). Build passes. Screenshots left for the owner.
- **Step 7** `91c0d7a`: README, getting started and interaction design docs updated.
- `make verify`: build, `BonkChecks` and 56 XCTests pass.

### Assumptions

- `Shortcut` lives in `ShortcutMonitor.swift`. It is stored as JSON under the defaults key `shortcut`. The old `shortcutKey` value is read for migration and left in place.
- Migration uppercases the old value before the A–Z lookup. A stored `shortcut` value that cannot be decoded becomes ⇧⌘B.
- Validation is `Shortcut.recorded(keyCode:modifiers:characters:)`, which throws a `ShortcutRejection` with the reason. A printable key is a single character from letters, digits, punctuation or symbols. Space is refused. The label is `characters(byApplyingModifiers: [])`, uppercased.
- The recorder calls `AppModel.setShortcut` on the recorded key's key-up, not on key-down. Registration therefore happens only after release, and `resume()` is then a no-op. A refused combination shows its reason and recording continues. Clicking the button again also stops recording.
- When re-arming fails after a failed attempt, the interceptor reports `eventTapDisabled` and `GuardController` also fails open on `!isRunning`. `failOpen` can run twice; it is idempotent.
- `stop()` clears `allowsOwnerInput` without re-arming, because the tap is already gone.
- `AppModel` imports Carbon for `eventHotKeyExistsErr`, which gives the "already used by another app" message.
- The settings window keeps its old style mask (not resizable) after `NSWindow(contentViewController:)`.

### Deviations

- `Checks/PolishChecks.swift:260` asserted `input.starts == 2` after a failed attempt. It is the BonkChecks mirror of `GuardControllerTests.swift:125`, which the plan updates for the same decided behaviour. It now asserts `starts == 1 && !allowsOwnerInput`. This was not treated as drift: the behaviour change is the one Decision 2 makes, and the plan names `PolishInput` and `make check`.
- Step 5 removes the `keyConfirmation` state, because Decision 9 removes the "Saved" text. `saveAPIKey` also ends the replacing state. Storage calls are unchanged.
- Step 7 also corrects two `docs/interaction-design.md` sentences that Steps 2 and 5 made false: the event tap "pauses" during authentication, and the old Jev credential card text.

### Left

- **Manual checks for the owner** (none were run):
  - Criterion 1, the release gate for Steps 1–2: the gesture matrix in Classic, Screen off and Agents, with two Spaces and a second display.
  - Criterion 2: gestures while the unlock sheet shows, and right after a failed or cancelled unlock.
  - Criterion 4 and the Step 2 manual check: Touch ID, a wrong password then the right one, and "Keep Bonk On" all behave as before.
  - Drift checks from "For the implementer": the Carbon registration asks for no permission, and the tap can be turned back on during pass-through in practice.
  - Criteria 5 and 6: the shortcut from Safari or Chrome (where ⇧⌘B is also a browser shortcut), from a password field, after a rebuild with a stale Accessibility grant, and while guarding.
  - Criterion 7: record a new shortcut, relaunch, refuse ⌥K and ⇧K, record a combination another app holds, hold the new combination while recording, and record the current shortcut again.
  - Criterion 8: first launch with an existing `shortcutKey` letter.
  - Criteria 9 and 10: Settings screenshots with the scroll bar at "Always" and at "When scrolling"; the Jev area with no key, a saved key and while replacing.
- **Not built:**
  - `ShortcutMonitor` has no `deinit`. The Carbon handler holds an unretained pointer; `AppModel` lives for the whole app and calls `stop()` on shutdown.
  - Keypad digits pass validation as printable. The menu then shows the main-row digit.
