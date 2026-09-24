Bonk

A playful input lock for macOS

Platform: macOS
Form factor: Menu bar application
Implementation: Native Swift / SwiftUI + AppKit
Version: MVP / v1

⸻

1. Product Summary

Bonk is a lightweight macOS menu-bar utility that lets a user temporarily disable interaction with their Mac while keeping the computer awake and the screen visible.

When Bonk is enabled:

* The Mac remains awake.
* The display remains visible.
* Keyboard input is blocked.
* Trackpad and mouse interactions are blocked.
* Attempted interaction triggers a playful animated character.
* The character reacts to what the person is trying to do.
* The character directs the user toward Touch ID.
* Successful owner authentication disables Bonk and restores normal input.

Bonk is intended for situations where the user wants their Mac to continue displaying or running something but does not want someone nearby interacting with it.

The product should feel less like a security utility and more like a tiny character whose job is to guard the Mac.

⸻

2. Core Product Idea

The basic interaction is:

Click Bonk → Mac stays awake → input is blocked → someone touches Mac → character appears → BONK → Touch ID → unlocked

Bonk does not replace the macOS lock screen.

Instead, it creates a temporary guarded state on top of the existing desktop.

The desktop remains visible and applications continue running normally underneath Bonk.

⸻

3. Primary Use Cases

Desk

The user steps away from their desk but wants something on their screen to remain running or visible.

Examples:

* long-running development task
* build
* download
* dashboard
* presentation
* monitoring screen
* video
* demo
* local server
* test suite

The user activates Bonk before leaving.

Someone touching the Mac cannot interact with the applications underneath.

⸻

Cleaning

The user wants to clean their keyboard or trackpad without accidentally triggering inputs.

Bonk temporarily disables them.

⸻

Pets / Children

The Mac is running something, but accidental keyboard or trackpad input should not affect it.

Bonk intercepts the interaction.

⸻

Fun Desk Security

Someone tries touching the Mac while the owner is away.

Instead of immediately showing a boring lock screen, a little character appears and tells them to stop.

⸻

4. Product Principles

4.1 One-click activation

Bonk should take one action to activate.

No dialogs.

No confirmation.

Click:

Bonk this Mac

The Mac is immediately guarded.

⸻

4.2 One-action unlock

Unlocking should primarily use Touch ID.

The user authenticates successfully and Bonk immediately disappears.

There should not be another confirmation button.

⸻

4.3 Desktop remains visible

Bonk should not cover the desktop with a conventional lock screen.

The user’s current screen remains visible.

Bonk adds transparent overlays above it.

⸻

4.4 The character is the interface

Avoid conventional warning dialogs wherever possible.

Instead of:

Keyboard input has been disabled.

The character reacts to the keyboard.

Instead of:

Authentication required.

The character points toward Touch ID.

Bonk should communicate primarily through motion and short pieces of text.

Jev, TypeSafe AI’s structured decision model, should select the character’s reaction from a fixed set of reaction intents using privacy-safe interaction state.

Jev does not generate arbitrary dialogue or control the guard. Animation assets, sound effects and text remain curated and local to the application.

⸻

4.5 Never trap the owner

Bonk controls system input, so failure handling is critical.

There must always be a reliable recovery mechanism if:

* Touch ID fails
* Touch ID is unavailable
* the event interceptor crashes
* the overlay crashes
* macOS permissions change
* an external keyboard behaves unexpectedly

Bonk should fail open, not fail locked.

If Bonk itself crashes, normal input should immediately return.

⸻

5. Menu Bar Experience

Bonk runs primarily as a menu-bar application.

No Dock icon is required during normal operation.

Example menu:

🐾 Bonk
Bonk this Mac        ⇧⌘B
───────────────────────
Keep Awake           ✓
Character          Cat >
───────────────────────
Settings...
About Bonk
Quit

The exact keyboard shortcut should be configurable.

⸻

6. Bonk States

Bonk has four primary states.

IDLE

Normal Mac operation.

Input is untouched.

Character is inactive.

⸻

ARMED

Bonk has been activated.

Keyboard and pointing-device interactions are intercepted.

Mac is kept awake.

Transparent overlays exist over every display.

⸻

REACTING

Someone attempts interaction.

Bonk determines what happened:

* mouse movement
* click
* scroll
* keypress
* repeated keypress
* shortcut attempt

The character responds appropriately.

⸻

AUTHENTICATING

Bonk requests owner authentication.

Touch ID is presented.

Success:

AUTHENTICATING → IDLE

Failure:

AUTHENTICATING → ARMED

⸻

7. Input Behaviour

Bonk needs to distinguish between input types even though those inputs should not reach the underlying application.

Mouse Movement

Detect movement.

Do not allow the movement to interact with the underlying application.

Character notices the cursor.

Possible reaction:

Character looks toward cursor.

Continued movement:

Character follows it.

⸻

Mouse Click

Click is swallowed.

Character runs toward cursor.

Character performs a:

BONK

animation.

Cursor could visually bounce/shake as part of the overlay animation.

⸻

Rapid Clicking

First click:

Bonk.

Second click:

Character looks annoyed.

Repeated clicks:

Character bonks repeatedly.

Eventually:

seriously?

⸻

Keyboard

Keypresses are swallowed.

First key:

Character looks toward the keyboard/user.

More typing:

Character covers its ears.

Keyboard mashing:

Character becomes increasingly annoyed.

Possible messages:

nope.

stop that.

that’s not yours.

BONK.

⸻

Scroll

Scrolling is swallowed.

Character gets pushed/slides across the screen.

Large scroll:

Character tumbles.

⸻

Keyboard Shortcuts

Attempts such as:

⌘ Tab
⌘ Space
⌘ Q

should not reach applications where macOS allows Bonk to intercept them.

Character could hold up a small:

🚫

sign.

Bonk should not attempt to interfere with protected system-level security shortcuts or operating-system recovery mechanisms that macOS intentionally reserves.

⸻

8. Character System

The character is the primary personality of Bonk.

For v1, ship one excellent character instead of several mediocre ones.

Recommended first character:

Cat

The cat lives in the menu bar while Bonk is idle.

When Bonk activates, the cat becomes a guard.

Possible visual change:

* sunglasses
* tiny security cap
* baton
* serious expression

⸻

9. Character States

The character animation system should support:

idle
sleeping
notice
walk
run
point
bonk
annoyed
angry
dragged
tumble
celebrate
disappear

These should be reusable animation states rather than individually scripted sequences.

⸻

10. Personality Escalation

Bonk should remember interaction intensity during the current guarded session.

Level 0

No interaction.

Character sleeps somewhere unobtrusive.

Level 1

Mouse moves.

Character wakes up.

Level 2

Click.

Character bonks cursor.

Level 3

More interaction.

Character becomes visibly annoyed.

Level 4

Repeated keyboard/mouse input.

Character becomes dramatic.

Example:

dude.

Level 5

Persistent attempts.

Character walks toward the Touch ID side of the screen and points upward.

Use the finger.

The escalation resets after successful authentication.

10.1 Jev Reaction Engine

Jev is the decision engine for character reactions.

Documentation:

https://docs.typesafe.ai/introduction

Bonk should send Jev a small structured snapshot of the current guarded session and ask it to choose among reaction intents that the application already knows how to render.

The reaction flow is:

InputInterceptor
      ↓
InteractionAggregator
      ↓
ReactionController
      ↓
JevReactionProvider
      ↓
validated ReactionPlan
      ↓
CharacterEngine

The event-tap callback must never perform network work or wait for Jev. It should suppress/classify the event, publish a privacy-safe signal and return immediately.

InteractionAggregator coalesces bursts of activity into a snapshot. A snapshot may include:

* interaction category, such as mouseMovement, click, rapidClick, keyboardActivity, scroll or shortcutAttempt
* recent interaction counts
* interaction-rate bucket
* guarded-session duration bucket
* current escalation level
* current character state
* current display identifier local to the session
* coarse cursor region when needed for animation planning

A snapshot must never include:

* typed characters or key codes that reveal content
* application names, window titles or visible screen content
* screenshots
* clipboard contents
* filenames, document contents or URLs
* precise historical cursor paths

Jev should use a Choice question to select one allowlisted reaction intent, for example:

notice
followCursor
bonk
repeatBonk
annoyed
angry
blockShortcut
tumble
pointToTouchID

It may also use a Score question to estimate reaction intensity. All relevant questions should be sent together in one request against the same snapshot.

The response is converted into a local ReactionPlan. Bonk accepts only known enum values and bounded numeric values. Unknown, malformed or low-confidence answers are discarded.

The ReactionController must:

* debounce/coalesce high-frequency activity
* allow at most a small bounded number of requests in flight
* apply a short timeout suitable for interactive animation
* ignore responses from a previous guarded session
* ignore responses that are stale relative to newer interaction
* cancel outstanding work when Bonk is disabled
* fall back to LocalReactionProvider on timeout, offline state, rate limiting, invalid output or low confidence

LocalReactionProvider implements deterministic versions of the core reactions. It provides an immediate reaction while Jev is pending and is the complete offline fallback.

Jev may choose personality and presentation only. It must never decide whether input is intercepted, whether Guard Mode remains active, whether authentication is accepted, whether permissions are sufficient or whether cleanup runs.

The path to owner authentication must remain deterministic and available regardless of Jev’s output.

⸻

11. Unlock Experience

After an interaction, Bonk should provide an obvious path for the owner to unlock.

Character walks toward the upper-right region of the screen.

Character points toward the physical Touch ID / power-button area.

Text:

Owner?

Then macOS authentication is initiated using LocalAuthentication.

Touch ID prompt:

Unlock Bonk

Successful authentication:

Character celebrates.

Possible animation:

✨ BONK OFF ✨

The overlays disappear.

Input interception stops.

Normal operation resumes.

⸻

12. Authentication Fallback

Touch ID may not always be available.

Examples:

* Mac without Touch ID
* external keyboard
* Touch ID temporarily unavailable
* too many failed fingerprint attempts
* macOS requires password

Bonk should allow the authentication mechanisms macOS considers appropriate through LocalAuthentication.

Bonk should never implement its own password database.

Authentication belongs to macOS.

⸻

13. Multi-Monitor Support

Every connected display must be protected.

Bonk creates one transparent overlay per display.

The character normally appears on the display receiving interaction.

If the cursor crosses displays, the character can eventually follow it.

Disconnecting or connecting a display while Bonk is active must not expose an interactive display.

Display configuration changes should trigger overlay reconstruction.

⸻

14. Keep Awake

When Bonk is active, it prevents idle sleep.

The desired default behaviour:

System sleep     Prevented
Display sleep    Prevented
Screen saver     Prevented where appropriate

The exact sleep behaviour should eventually be configurable.

For MVP:

Bonk active = Mac stays awake.

Bonk should release its power assertion immediately when disabled or terminated.

⸻

15. Permissions

Bonk will likely require macOS permissions to globally observe/intercept relevant input.

The onboarding experience should explain why each permission is needed.

Example:

Bonk needs permission to guard your keyboard.

Without it, Bonk can’t stop someone from interacting with your Mac.

Open System Settings

After permission is granted, Bonk verifies it automatically.

Do not ask for permissions unrelated to the core functionality.

⸻

16. First Launch

Keep onboarding short.

Screen 1

Meet Bonk.

Your tiny Mac bodyguard.

[Continue]

Screen 2

Bonk needs access to your keyboard and mouse.

That’s how it stops unwanted input.

[Enable Access]

Screen 3

Make Bonk more expressive.

AI reactions send TypeSafe AI a small anonymous summary such as “rapid clicking” or “keyboard activity.” Bonk never sends what was typed or what is on the screen.

[Use AI Reactions]

[Keep Reactions On Device]

Screen 4

Try it.

Click the menu-bar icon and choose:

Bonk this Mac

[Done]

No account.

No signup.

No Bonk cloud account setup.

⸻

17. Settings

Keep settings minimal.

General

Launch Bonk at login

On / Off

Keep Mac awake while Bonked

On / Off

Default: On

⸻

Character

Character:

Cat

Future versions can add additional characters.

⸻

Sound

Character sounds

On / Off

Default: On

Sounds should be subtle.

⸻

Reactions

AI-powered reactions

On / Off

Default: Off until the user makes an informed choice during onboarding

When enabled, Jev selects from Bonk’s curated reaction set using aggregated interaction metadata.

When disabled or unavailable, Bonk uses its local reaction provider.

⸻

Shortcut

Toggle Bonk

Default:

⇧⌘B

User configurable.

⸻

18. Sound Design

Bonk can use very small sound effects.

Examples:

Click blocked:

bonk

Repeated click:

bonk bonk

Character annoyed:

small grunt/meow

Unlock:

small success sound

Sound should never become obnoxious.

The application should also work perfectly with sound disabled.

⸻

19. Visual Architecture

Bonk should use transparent, borderless AppKit windows positioned above ordinary applications.

Conceptually:

┌─────────────────────────────────────────┐
│              Bonk Overlay               │
│                                         │
│                         🐱              │
│                        BONK!            │
│                                         │
│                                         │
├─────────────────────────────────────────┤
│       Existing macOS Desktop            │
│       Applications continue running     │
└─────────────────────────────────────────┘

The overlay should remain visually transparent except for:

* character
* speech bubbles
* animation effects
* authentication guidance

⸻

20. Technical Architecture

Recommended architecture:

BonkApp
   │
   ├── MenuBarController
   │
   ├── GuardController
   │      │
   │      ├── InputInterceptor
   │      │      └── CGEventTap
   │      │
   │      ├── AwakeManager
   │      │
   │      ├── OverlayManager
   │      │      └── NSWindow per display
   │      │
   │      └── AuthenticationManager
   │             └── LocalAuthentication
   │
   ├── CharacterEngine
   │      ├── StateMachine
   │      ├── AnimationController
   │      └── ReactionController
   │             ├── InteractionAggregator
   │             ├── ReactionProvider
   │             │      ├── JevReactionProvider
   │             │      └── LocalReactionProvider
   │             └── ReactionValidator
   │
   └── SettingsManager

⸻

21. Technology

Language

Swift

UI

SwiftUI

Use for:

* menu bar
* settings
* onboarding
* simple controls

Window Management

AppKit

Use for:

* transparent overlays
* display management
* window levels
* animation surfaces

Input

Core Graphics event taps.

CGEventTap

Responsible for:

* observing keyboard
* observing mouse
* suppressing permitted events
* classifying interactions

Authentication

LocalAuthentication.

Use:

LAContext

Prefer device-owner authentication so macOS controls the available authentication method.

Reaction Decisions

Use TypeSafe AI’s Jev model through:

POST https://api.typesafe.ai/v1/systemone

The native Swift application should call the HTTPS API using URLSession and Codable request/response types.

Production releases should pin a tested, versioned Jev model identifier. Floating aliases such as jev-latest may be used during development, but should not silently change reaction behaviour in a released build.

Choice and Score outputs must be mapped into local Swift enums and bounded values before they reach CharacterEngine.

Keep Awake

Use macOS power-management/activity APIs such as ProcessInfo activity assertions or appropriate IOKit power assertions depending on the final behaviour required.

⸻

22. Character Rendering

Avoid introducing a full game engine for v1.

Bonk does not need Unity, Godot, Phaser, or Electron.

Character animation can be implemented using native macOS rendering.

Potential asset formats:

* sprite sheets
* PNG sequences
* vector assets
* lightweight animation files

The CharacterEngine should abstract animation implementation so the rendering mechanism can change later.

⸻

23. Character Coordinate System

The character should understand:

* cursor position
* screen bounds
* screen edges
* menu bar location
* Touch ID direction
* current display
* character position

This allows behaviours such as:

Chase cursor

character.position → cursor.position

Bonk cursor

runTo(cursor)
play(.bonk)

Point toward Touch ID

walkTo(topRight)
play(.point)

The character does not need physics simulation.

Simple easing and predefined animation states are sufficient.

⸻

24. Security Model

Bonk is not a replacement for macOS screen locking.

It should not claim to provide the same security guarantees as macOS’s native lock screen.

Bonk is an input guard intended to prevent casual or accidental interaction while leaving the current screen visible.

Sensitive information visible on the screen remains visible.

If the user requires actual workstation security, macOS Lock Screen remains the appropriate mechanism.

⸻

25. Failure Safety

This is one of the most important engineering requirements.

Input interception must never leave the user permanently unable to control the Mac.

Event tap failure

Immediately disable Guard Mode.

Overlay crash

Disable Guard Mode.

Main process crash

macOS should naturally remove process-owned event taps, restoring input.

Authentication subsystem failure

Restore a safe recovery path rather than indefinitely blocking input.

Jev unavailable, slow or returns an invalid response

Use LocalReactionProvider.

Do not change Guard Mode, authentication availability or input cleanup behaviour.

If Guard Mode ends while a Jev request is active, cancel the request and ignore any response that still arrives.

Permission revoked

Disable Guard Mode.

Notify user after input has been restored.

Application quit

Always:

stopInputInterceptor()
releasePowerAssertion()
destroyOverlays()

Cleanup should also occur during termination.

⸻

26. Privacy

Bonk observes keyboard events only for the purpose of blocking/classifying interaction while Guard Mode is active.

Bonk must never record typed characters.

For example, CharacterEngine should receive:

keyboardActivity

rather than:

key = "p"

There is no reason for Bonk to know what the person typed.

Similarly:

* no keylogging
* no raw input history
* no screenshots
* no clipboard reading
* no application, window or document inspection

Jev receives only the minimum aggregated interaction metadata needed to select a reaction.

Actual typed content must never enter application logs, analytics, Jev requests or error reports. Raw events should be reduced to privacy-safe categories before leaving InputInterceptor.

Cloud-assisted reactions must be disclosed during onboarding and controllable in settings. Disabling them selects LocalReactionProvider without weakening any guard behaviour.

Bonk should not persist Jev request payloads or responses beyond the active guarded session.

⸻

27. Data and Networking

No Bonk account is required.

No application database is required.

No telemetry is required for core functionality.

Preferences can live locally using macOS preferences/UserDefaults.

Guard Mode, authentication, cleanup and LocalReactionProvider must work completely offline.

Jev-powered reactions require network access to TypeSafe AI. Network availability must never be a prerequisite for activating or disabling Bonk.

A production TypeSafe API key must never be embedded in the application binary or committed to source control.

For internal prototypes, use a developer-supplied key loaded at runtime from secure local configuration.

Before public distribution, use one of:

* a minimal Bonk-owned credential proxy
* a user-supplied TypeSafe API key stored in Keychain
* a TypeSafe-supported client credential that is explicitly safe to distribute

If Bonk operates a proxy, it should be stateless for reaction traffic, avoid payload logging, enforce request limits and retain no interaction state.

⸻

28. MVP Scope

Version 0.1 should implement only:

1. Menu-bar application
2. Activate Bonk
3. Prevent idle sleep
4. Intercept keyboard input
5. Intercept mouse/trackpad interaction
6. Transparent overlay
7. Basic character
8. Mouse movement reaction
9. Click → BONK animation
10. Keyboard → annoyed animation
11. Touch ID authentication
12. Successful authentication restores input
13. Multi-monitor support
14. Safe failure handling
15. Privacy-safe InteractionAggregator
16. Jev Choice/Score reaction decision
17. Confidence and schema validation
18. Deterministic LocalReactionProvider fallback
19. Network-disabled acceptance test
20. AI-reaction disclosure and consent control

Do not build customization yet.

⸻

29. v1 Scope

Once the core mechanism is reliable:

* polished character animation
* interaction escalation
* sounds
* configurable shortcut
* launch at login
* onboarding
* preferences
* multiple interaction reactions
* scroll animation
* sleeping character
* polished Touch ID sequence
* cloud-assisted reactions setting and onboarding disclosure
* production-safe Jev credential delivery

This becomes the first distributable version of Bonk.

⸻

30. Future Ideas

These should explicitly stay outside MVP.

Characters

Cat
Dog
Robot
Duck
Security guard
Tiny monster

⸻

Character Packs

Different personalities could have completely different reactions.

Example:

Polite Cat

Excuse me.

This isn’t your Mac.

versus:

Angry Goose

NO.

BONK.

⸻

Auto Bonk

Automatically activate after a configurable period of inactivity.

Example:

Bonk after 5 minutes.

⸻

Apple Watch

Potential future proximity concept:

User walks away wearing their Apple Watch.

Bonk activates.

User returns.

Bonk recognizes proximity.

Authentication requirements should still follow macOS security capabilities.

⸻

Bonk Counter

Optional local statistic:

Bonk protected your Mac from 17 interactions today.

No actual input contents are stored.

⸻

Intruder Mode

The character reacts increasingly dramatically to persistent attempts.

No photos.

No recording.

No surveillance.

Just increasingly ridiculous animations.

⸻

31. Brand

Name

Bonk

Short, memorable and directly connected to the primary interaction.

Possible tagline

Hands off. Bonk on.

Alternative:

Your Mac has a bodyguard.

Alternative:

Touch my Mac. Get bonked.

⸻

32. Icon

A simple character face with a tiny raised paw/weapon/object ready to bonk.

The icon should remain recognizable at macOS menu-bar size.

Idle:

🐱

Guarding:

😼

The production artwork should be custom rather than emoji.

⸻

33. Product Personality

Bonk should be:

Useful first.

Funny second.

It should not feel like a joke application that happens to block input.

The input interception, authentication and failure recovery need to be extremely reliable.

The humor comes from what Bonk does after someone tries interacting with the computer.

⸻

34. MVP Success Criteria

A successful first prototype should demonstrate one complete interaction:

User clicks Bonk
       ↓
Mac stays awake
       ↓
Input interception starts
       ↓
User moves cursor
       ↓
Character notices
       ↓
User clicks
       ↓
   BONK!
       ↓
Character points toward Touch ID
       ↓
Touch ID prompt
       ↓
Fingerprint succeeds
       ↓
Character celebrates
       ↓
Overlay disappears
       ↓
Keyboard + mouse work normally

If this interaction feels reliable and entertaining, the fundamental product works.

The same complete interaction must also succeed with networking disabled. In that case LocalReactionProvider supplies the character reactions and no guard, authentication or cleanup behaviour changes.

Privacy verification must confirm that outbound Jev requests contain only the documented aggregated interaction fields and never contain typed content, key codes, application context or screen content.

⸻

35. Development Order

Build the product vertically rather than building the animation system first.

Prototype 1 — Input

Menu-bar button → intercept keyboard/mouse → restore input safely.

No character.

Prototype 2 — Authentication

Intercept → Touch ID → restore.

This validates the most important technical assumptions.

Prototype 3 — Overlay

Add transparent always-on-top overlays across displays.

Prototype 4 — Character

Render a placeholder character at cursor coordinates.

Prototype 5 — Bonk

Click → character moves toward cursor → BONK animation.

Prototype 6 — Jev Reaction Engine

Aggregate sanitized interaction signals → ask Jev for an allowlisted reaction → validate the response → render it.

Simulate timeouts, offline state, rate limits, invalid responses and stale responses. Every case must fall back locally without affecting Guard Mode.

Prototype 7 — Personality

Add state machine, escalation, sleeping, pointing and reactions.

Prototype 8 — Polish

Onboarding, settings, sounds, icon, animations and packaging.

The first engineering milestone should therefore be extremely small:

Can a native macOS menu-bar app safely suppress the intended keyboard/mouse events and reliably restore them after LocalAuthentication succeeds?

Everything else in Bonk can be built around that answer.

Before spending time on polished character assets, build Prototype 1 and Prototype 2. The input-blocking and security boundaries are the main technical risk. Once those work reliably, integrate Jev behind the ReactionProvider boundary without placing it on the safety-critical path.
