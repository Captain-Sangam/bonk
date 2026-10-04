import AppKit
import BonkCore
import Foundation

// Executable regressions also run on Macs with Command Line Tools but no XCTest.
@MainActor
internal enum PolishChecks {
    static func run() async throws {
        try gesturesAndLocalSelection()
        try deadlinesAndCursor()
        try await deferredMessagesAndRest()
        try await sessionCleanup()
        try await jevPacingAndCancellation()
        try await queuedJevKeepsLocalFallback()
        try await authenticationResume()
        print("Polish checks passed: gestures, local selection, deadlines, cursor, deferred text, rest/wake, Jev, session cleanup, authentication resume")
    }

    private static func gesturesAndLocalSelection() throws {
        var aggregator = InteractionAggregator()
        let start = Date(timeIntervalSince1970: 1_000)
        aggregator.reset(at: start.addingTimeInterval(-600))
        var snapshot: ReactionSnapshot!
        for index in 0...960 {
            snapshot = aggregator.record(
                InteractionSignal(kind: .mouseMovement, timestamp: start.addingTimeInterval(Double(index) / 120), magnitude: 100),
                characterState: "walk", displayIndex: nil, cursorRegion: .center
            )
            try require(snapshot.escalationLevel <= 2 && snapshot.interactionRate == .low, "Continuous drift escalated")
            try require(LocalReactionProvider().immediateReaction(for: snapshot).intent != .promptDoubleEscape, "Drift prompted unlock")
        }
        try require(snapshot.recentEventCounts["mouseMovement"] == 1 && snapshot.movementGestureDuration == 8, "Continuous gesture reset after five seconds")
        try require(LocalReactionProvider().immediateReaction(for: snapshot).intent == .stalkCursor, "Sustained motion did not stalk")
        let encoded = try JSONEncoder().encode(snapshot)
        try require(!String(decoding: encoded, as: UTF8.self).contains("movementGestureDuration"), "Local gesture duration entered wire format")
        let decoded = try JSONDecoder().decode(ReactionSnapshot.self, from: encoded)
        try require(decoded.movementGestureDuration == 0, "Gesture duration decoding did not default locally")

        aggregator = InteractionAggregator(gestureGap: 0.1)
        aggregator.reset(at: start)
        for index in 0..<12 {
            snapshot = aggregator.record(InteractionSignal(kind: .mouseMovement, timestamp: start.addingTimeInterval(Double(index) * 0.2)),
                characterState: "walk", displayIndex: nil, cursorRegion: .center)
        }
        try require(snapshot.recentEventCounts["mouseMovement"] == 12 && snapshot.escalationLevel == 2, "Gesture grouping/cap failed")
        let frantic = aggregator.record(InteractionSignal(kind: .mouseMovement, timestamp: start.addingTimeInterval(10), magnitude: 1_500),
            characterState: "walk", displayIndex: nil, cursorRegion: .center)
        try require(LocalReactionProvider().immediateReaction(for: frantic).intent == .pounce, "First frantic gesture did not pounce")

        aggregator.reset(at: start)
        var beats: [String] = []
        var previous: ReactionPlan?
        for index in 0..<10 {
            snapshot = aggregator.record(InteractionSignal(kind: .keyboardActivity, timestamp: start.addingTimeInterval(Double(index) * 0.01)),
                characterState: "idle", displayIndex: nil, cursorRegion: .unknown, recentCharacterBeats: beats)
            let plan = LocalReactionProvider().immediateReaction(for: snapshot)
            let expected: ReactionIntent = index < 2 ? .annoyed : index < 5 ? .coverEars : .angry
            try require(plan.intent == expected, "Typing pace selected the wrong intent")
            if let previous {
                try require(previous.intent != plan.intent || previous.tone != plan.tone, "Consecutive identical intent/tone")
            }
            beats.append("\(plan.intent.rawValue)|\(plan.tone.rawValue)|\(plan.pacing.rawValue)")
            previous = plan
        }
    }

    private static func deadlinesAndCursor() throws {
        let (controller, character) = localController()
        defer { controller.endSession() }
        let start = Date()
        controller.handle(InteractionSignal(kind: .mouseMovement, timestamp: start))
        let initial = character.presentation
        guard let screen = NSScreen.screens.first else { throw Failure.failed("No display for cursor checks") }
        controller.handle(InteractionSignal(kind: .mouseMovement, timestamp: start.addingTimeInterval(1),
            globalLocation: CGPoint(x: screen.frame.midX, y: screen.frame.midY), magnitude: 1_500, deltaX: -10))
        try require(character.presentation.state == initial.state && character.presentation.message == initial.message, "Movement bypassed window")
        try require(character.presentation.position == initial.position && character.presentation.activeDisplayNumber == initial.activeDisplayNumber, "Movement carried the bubble away")
        try require(character.cursorPresentation.position != nil && character.presentation.lookX != initial.lookX && character.presentation.facing == -1, "Ambient gaze/cursor froze")
        controller.handle(InteractionSignal(kind: .scroll, timestamp: start.addingTimeInterval(2), magnitude: 20))
        try require(character.presentation.variant == initial.variant, "Scroll bypassed window")
        for (index, kind) in [InteractionKind.click, .rapidClick, .keyboardActivity, .keyboardActivity, .shortcutAttempt].enumerated() {
            let variant = character.presentation.variant
            controller.handle(InteractionSignal(kind: kind, timestamp: start.addingTimeInterval(2 + Double(index + 1) * 0.1)))
            try require(character.presentation.variant > variant && character.presentation.message == initial.message, "Deliberate input did not react immediately while preserving text")
        }
        let deliberate = character.presentation
        controller.handle(InteractionSignal(kind: .mouseMovement, timestamp: start.addingTimeInterval(4), magnitude: 1_500))
        try require(character.presentation.variant == deliberate.variant, "Movement ignored state deadline")
        controller.handle(InteractionSignal(kind: .mouseMovement, timestamp: start.addingTimeInterval(6.5), magnitude: 1_500))
        try require(character.presentation.state == .pounce && character.presentation.variant > deliberate.variant, "Exact deadline blocked eligible movement")

        let plan = ReactionPlan(intent: .bonk, intensity: 0.5, confidence: 1, source: .local, dialogueID: "bonk.playful.0")
        let freshCharacter = CharacterEngine { false }
        freshCharacter.apply(plan, near: nil, preservingMessage: true)
        let pose = freshCharacter.presentation
        freshCharacter.publishMessage(for: plan)
        try require(freshCharacter.presentation.message == "BONK!", "Unpublished line was recorded as used")
        try require(freshCharacter.presentation.variant == pose.variant && freshCharacter.presentation.reactionStartedAt == pose.reactionStartedAt, "Text-only publication replayed pose")
    }

    private static func deferredMessagesAndRest() async throws {
        let (controller, character) = localController(displayInterval: 0.12, restInterval: 0.4)
        defer { controller.endSession() }
        controller.handle(InteractionSignal(kind: .mouseMovement))
        let firstText = character.presentation.message
        try await Task.sleep(nanoseconds: 30_000_000)
        controller.handle(InteractionSignal(kind: .click))
        controller.handle(InteractionSignal(kind: .click))
        let pose = character.presentation
        try require(pose.state == .swat && pose.message == firstText, "Mid-window click replaced text")
        try await Task.sleep(nanoseconds: 130_000_000)
        try require(isDialogue(character.presentation.message, for: .swat), "Latest lone click did not publish at deadline")
        try require(character.presentation.variant == pose.variant && character.presentation.reactionStartedAt == pose.reactionStartedAt, "Deferred text replayed animation")
        let published = character.presentation
        controller.handle(InteractionSignal(kind: .mouseMovement, magnitude: 1_500))
        try require(character.presentation.variant == published.variant && character.presentation.message == published.message, "Fresh deferred text did not restart reading window")
        controller.handle(InteractionSignal(kind: .keyboardActivity))
        controller.handle(InteractionSignal(kind: .scroll, timestamp: Date().addingTimeInterval(1), magnitude: 20))
        let fresh = character.presentation
        try await Task.sleep(nanoseconds: 150_000_000)
        try require(character.presentation == fresh, "Older deferred candidate overwrote fresher text")

        let (idleController, idleCharacter) = localController(displayInterval: 0.1, restInterval: 0.02)
        defer { idleController.endSession() }
        idleController.handle(InteractionSignal(kind: .mouseMovement))
        try await Task.sleep(nanoseconds: 45_000_000)
        try require(idleCharacter.presentation.message != nil && idleCharacter.presentation.state != .sleeping, "Rest hid young text")
        try await Task.sleep(nanoseconds: 90_000_000)
        try require(idleCharacter.presentation.state == .sleeping && idleCharacter.presentation.message == nil && idleCharacter.presentation.tone == .sleepy, "Idle did not rest and hide bubble")
        idleController.handle(InteractionSignal(kind: .mouseMovement))
        try require(idleCharacter.presentation.state == .notice && idleCharacter.presentation.message != nil && idleCharacter.presentation.intensity <= 0.4, "Wake was not immediate and gentle")
        idleController.handle(InteractionSignal(kind: .click))
        try await Task.sleep(nanoseconds: 130_000_000)
        try require(isDialogue(idleCharacter.presentation.message, for: .bonk), "Rest won a race against due click text")
        try await Task.sleep(nanoseconds: 120_000_000)
        try require(idleCharacter.presentation.state == .sleeping && idleCharacter.presentation.message == nil, "Rest did not follow deferred reading window")
    }

    private static func sessionCleanup() async throws {
        let (controller, character) = localController(displayInterval: 0.08, restInterval: 0.12)
        controller.handle(InteractionSignal(kind: .mouseMovement))
        controller.handle(InteractionSignal(kind: .click))
        controller.endSession()
        let stopped = character.presentation
        try await Task.sleep(nanoseconds: 180_000_000)
        try require(character.presentation == stopped, "Session-end left active timers")
        for _ in 0..<3 {
            controller.beginSession()
            controller.handle(InteractionSignal(kind: .mouseMovement))
            try require(character.presentation.state == .notice, "Session retained old deadlines or escalation")
            controller.handle(InteractionSignal(kind: .click))
        }
        controller.beginSession()
        defer { controller.endSession() }
        try await Task.sleep(nanoseconds: 100_000_000)
        try require(character.presentation.message == nil, "Old session published into a new session")
    }

    private static func jevPacingAndCancellation() async throws {
        let provider = HeldPolishProvider()
        let director = JevDirectorMonitor()
        let character = CharacterEngine { false }
        let controller = ReactionController(characterEngine: character, director: director,
            quietPeriodNanoseconds: 1_000_000, displayInterval: 0.15,
            providerFactory: { _ in provider }, configuration: { (true, "test-key") })
        controller.beginSession()
        controller.handle(InteractionSignal(kind: .click))
        let local = character.presentation
        try await waitForRequest(provider)
        await provider.releaseAll()
        try await Task.sleep(nanoseconds: 40_000_000)
        try require(character.presentation.message == local.message && character.presentation.variant == local.variant, "Jev cut short local text")
        try await Task.sleep(nanoseconds: 160_000_000)
        try require(isDialogue(character.presentation.message, for: .angry) && director.phase == .applied, "Jev text did not publish when eligible")
        try require(character.presentation.variant == local.variant, "Deferred Jev replayed pose")
        controller.endSession()

        // Providers deliberately ignore cancellation, exercising the controller's guards.
        for mode in ["rest", "input", "authentication", "end", "queued"] {
            let held = HeldPolishProvider()
            let fox = CharacterEngine { false }
            let reactions = ReactionController(characterEngine: fox, director: JevDirectorMonitor(),
                quietPeriodNanoseconds: 1_000_000, displayInterval: mode == "rest" ? 0.02 : 0.1,
                restInterval: mode == "rest" ? 0.05 : 20,
                providerFactory: { _ in held }, configuration: { (true, "test-key") })
            reactions.beginSession()
            reactions.handle(InteractionSignal(kind: .click))
            try await waitForRequest(held)
            if mode == "rest" { try await Task.sleep(nanoseconds: 90_000_000) }
            if mode == "input" { reactions.handle(InteractionSignal(kind: .keyboardActivity)) }
            if mode == "authentication" { reactions.pointToAuthentication() }
            if mode == "end" { reactions.endSession() }
            if mode == "queued" {
                await held.releaseAll()
                try await Task.sleep(nanoseconds: 15_000_000)
                reactions.handle(InteractionSignal(kind: .mouseMovement))
            }
            let preserved = fox.presentation
            if mode != "queued" { await held.releaseAll() }
            try await Task.sleep(nanoseconds: 140_000_000)
            try require(fox.presentation.state != .angry, "Stale Jev changed pose after \(mode)")
            if mode == "rest" || mode == "end" || mode == "queued" {
                try require(fox.presentation.message == preserved.message, "Stale Jev published after \(mode)")
            } else if mode == "authentication" {
                try require(fox.presentation.message == "Double Esc captured. Use Touch ID.", "Authentication guidance did not survive stale Jev")
            } else {
                try require(isDialogue(fox.presentation.message, for: .annoyed), "New local input lost its deferred dialogue")
            }
            reactions.endSession()
            await held.releaseAll()
        }
    }

    private static func queuedJevKeepsLocalFallback() async throws {
        for disableJev in [false, true] {
            var enabled = true
            let provider = HeldPolishProvider()
            let character = CharacterEngine { false }
            let controller = ReactionController(characterEngine: character, director: JevDirectorMonitor(),
                quietPeriodNanoseconds: 1_000_000, displayInterval: 0.15,
                providerFactory: { _ in provider }, configuration: { (enabled, "test-key") })
            controller.beginSession()
            controller.handle(InteractionSignal(kind: .mouseMovement))
            controller.handle(InteractionSignal(kind: .click))
            try await waitForRequest(provider)
            await provider.releaseAll()
            try await Task.sleep(nanoseconds: 15_000_000)
            if disableJev {
                enabled = false
            } else {
                controller.handle(InteractionSignal(kind: .mouseMovement))
            }
            try await Task.sleep(nanoseconds: 180_000_000)
            try require(character.presentation.state == .bonk && isDialogue(character.presentation.message, for: .bonk),
                "Discarding queued Jev lost the click's local dialogue (disabled: \(disableJev))")
            controller.endSession()
            await provider.releaseAll()
        }
    }

    private static func authenticationResume() async throws {
        let character = CharacterEngine { false }
        let reactions = ReactionController(characterEngine: character, director: JevDirectorMonitor(),
            displayInterval: 0.06, restInterval: 0.1, configuration: { (false, nil) })
        let input = PolishInput()
        let authentication = PolishAuthentication()
        let suite = "BonkPolishChecks.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let guardController = GuardController(settings: SettingsStore(defaults: defaults), inputInterceptor: input,
            awakeManager: PolishAwake(), overlayManager: PolishOverlay(), authenticationManager: authentication,
            reactionController: reactions, characterEngine: character)
        guardController.activate()
        defer { guardController.shutdown() }
        input.onAuthenticationGesture?()
        for _ in 0..<100 {
            if authentication.calls == 1 && guardController.status == .armed { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try require(authentication.calls == 1 && guardController.status == .armed && input.isRunning && input.starts == 2, "Authentication failure did not resume guard")
        try require(character.presentation.state == .sleeping && character.presentation.message == nil, "Authentication resume lost idle timer")
        input.onSignal?(InteractionSignal(kind: .mouseMovement))
        await Task.yield()
        try require(character.presentation.state == .notice, "Authentication resume did not wake")
        let text = character.presentation.message
        input.onSignal?(InteractionSignal(kind: .keyboardActivity))
        await Task.yield()
        try require(character.presentation.state == .annoyed && character.presentation.message == text, "Authentication resume lost pacing")
        try await Task.sleep(nanoseconds: 150_000_000)
        try require(character.presentation.state == .sleeping && character.presentation.message == nil, "Authentication resume lost rest")
    }

    private static func waitForRequest(_ provider: HeldPolishProvider) async throws {
        for _ in 0..<100 {
            if await provider.calls > 0 { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw Failure.failed("Jev request did not start")
    }

    private static func localController(displayInterval: TimeInterval = 4, restInterval: TimeInterval = 20) -> (ReactionController, CharacterEngine) {
        let character = CharacterEngine { false }
        let controller = ReactionController(characterEngine: character, director: JevDirectorMonitor(),
            displayInterval: displayInterval, restInterval: restInterval, configuration: { (false, nil) })
        controller.beginSession()
        return (controller, character)
    }

    private static func isDialogue(_ text: String?, for intent: ReactionIntent) -> Bool {
        guard let text else { return false }
        let phrases: [ReactionIntent: [String]] = [
            .bonk: ["BONK!", "Boop denied.", "Not today.", "Paw says no.", "Click rejected.", "Protected by fox.", "Access bonked.", "That's a bonk."],
            .swat: ["Swat.", "Hands off.", "Back you go.", "Paws on patrol.", "Shoo, cursor.", "Denied with style.", "A gentle warning.", "Boundary enforced."],
            .annoyed: ["Nope.", "I heard that.", "Keyboard privileges revoked.", "Those keys are guarded.", "Typing detected.", "Easy on the keyboard.", "Not a single letter.", "Paws over keys."],
            .angry: ["Seriously?", "You chose chaos.", "Now I'm fluffy and furious.", "That is quite enough.", "Emergency grump mode.", "The tail is puffed.", "Final furry warning.", "Patience depleted."]
        ]
        return phrases[intent, default: []].contains { text.hasPrefix($0) }
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure.failed(message) }
    }

    private enum Failure: Error { case failed(String) }
}

private actor HeldPolishProvider: ReactionProvider {
    private(set) var calls = 0
    private var replies: [CheckedContinuation<ReactionPlan, Never>] = []
    func reaction(for snapshot: ReactionSnapshot) async throws -> ReactionPlan {
        calls += 1
        return await withCheckedContinuation { replies.append($0) }
    }
    func releaseAll() {
        let pending = replies
        replies.removeAll()
        for reply in pending {
            reply.resume(returning: ReactionPlan(intent: .angry, intensity: 1, confidence: 1, source: .jev))
        }
    }
}

private final class PolishInput: InputIntercepting {
    var onSignal: ((InteractionSignal) -> Void)?
    var onAuthenticationGesture: (() -> Void)?
    var onFailure: ((BonkError) -> Void)?
    private(set) var isRunning = false
    private(set) var starts = 0
    func start(promptForPermission: Bool) throws { isRunning = true; starts += 1 }
    func stop() { isRunning = false }
}
private final class PolishAwake: AwakeManaging {
    func start() {}
    func stop() {}
}
@MainActor
private final class PolishOverlay: OverlayManaging {
    var onFailure: ((String) -> Void)?
    func show() throws {}
    func setCapturingInput(_ capture: Bool) {}
    func hide() {}
}
private final class PolishAuthentication: OwnerAuthenticating {
    private(set) var calls = 0
    func authenticateOwner() async throws {
        calls += 1
        throw BonkError.authenticationFailed("Cancelled")
    }
}
