import AppKit
import CoreGraphics
import Foundation
import XCTest
@testable import BonkCore

final class ReactionEngineTests: XCTestCase {
    func testAggregatorProducesOnlyCategoricalState() throws {
        var aggregator = InteractionAggregator()
        let start = Date(timeIntervalSince1970: 1_000)
        aggregator.reset(at: start)

        let snapshot = aggregator.record(
            InteractionSignal(
                kind: .keyboardActivity,
                timestamp: start.addingTimeInterval(2),
                globalLocation: CGPoint(x: 417, y: 219)
            ),
            characterState: "sleeping",
            displayIndex: 0,
            cursorRegion: .center
        )

        XCTAssertEqual(snapshot.interaction, .keyboardActivity)
        XCTAssertEqual(snapshot.recentEventCounts["keyboardActivity"], 1)
        XCTAssertEqual(snapshot.interactionRate, .low)
        XCTAssertEqual(snapshot.sessionDuration, .justStarted)
        XCTAssertEqual(snapshot.escalationLevel, 2)
        XCTAssertEqual(snapshot.motionEnergy, .still)
        XCTAssertEqual(snapshot.coarseDirection, .stationary)
        XCTAssertEqual(snapshot.typingPace, .slow)

        let encoded = String(data: try JSONEncoder().encode(snapshot), encoding: .utf8)!
        XCTAssertFalse(encoded.contains("417"))
        XCTAssertFalse(encoded.contains("219"))
        XCTAssertFalse(encoded.lowercased().contains("keycode"))
    }

    func testAggregatorEscalatesBurstActivity() {
        var aggregator = InteractionAggregator()
        let start = Date(timeIntervalSince1970: 2_000)
        aggregator.reset(at: start)

        var finalSnapshot: ReactionSnapshot?
        for index in 0..<12 {
            finalSnapshot = aggregator.record(
                InteractionSignal(
                    kind: .rapidClick,
                    timestamp: start.addingTimeInterval(Double(index) * 0.1)
                ),
                characterState: "bonk",
                displayIndex: 0,
                cursorRegion: .right
            )
        }

        XCTAssertEqual(finalSnapshot?.interactionRate, .high)
        XCTAssertEqual(finalSnapshot?.escalationLevel, 5)
        XCTAssertEqual(finalSnapshot?.recentEventCounts["rapidClick"], 12)
    }

    func testOldActivityFallsOutOfFiveSecondWindow() {
        var aggregator = InteractionAggregator()
        let start = Date(timeIntervalSince1970: 3_000)
        aggregator.reset(at: start)

        _ = aggregator.record(
            InteractionSignal(kind: .click, timestamp: start),
            characterState: "idle",
            displayIndex: nil,
            cursorRegion: .unknown
        )
        let snapshot = aggregator.record(
            InteractionSignal(kind: .scroll, timestamp: start.addingTimeInterval(6)),
            characterState: "bonk",
            displayIndex: nil,
            cursorRegion: .unknown
        )

        XCTAssertNil(snapshot.recentEventCounts["click"])
        XCTAssertEqual(snapshot.recentEventCounts["scroll"], 1)
    }

    func testLocalProviderMapsEveryInteraction() async throws {
        let provider = LocalReactionProvider()
        let expected: [InteractionKind: ReactionIntent] = [
            .mouseMovement: .notice,
            .click: .bonk,
            .rapidClick: .repeatBonk,
            .keyboardActivity: .annoyed,
            .scroll: .cling,
            .shortcutAttempt: .blockShortcut
        ]

        for (kind, intent) in expected {
            let snapshot = ReactionSnapshot(
                interaction: kind,
                recentEventCounts: [kind.rawValue: 1],
                interactionRate: .low,
                sessionDuration: .short,
                escalationLevel: kind == .mouseMovement ? 1 : 2,
                currentCharacterState: "idle",
                displayIndex: 0,
                cursorRegion: .center
            )
            let plan = try await provider.reaction(for: snapshot)
            XCTAssertEqual(plan.intent, intent)
            XCTAssertEqual(plan.source, .local)
        }
    }

    func testMotionAwareLocalReactionsHaveDistinctBehaviors() {
        let provider = LocalReactionProvider()
        let cases: [(ReactionSnapshot, ReactionIntent)] = [
            (
                makeLocalSnapshot(
                    interaction: .mouseMovement,
                    count: 2,
                    escalation: 2,
                    motionEnergy: .frantic
                ),
                .pounce
            ),
            (
                makeLocalSnapshot(
                    interaction: .mouseMovement,
                    count: 6,
                    escalation: 3,
                    motionEnergy: .gentle
                ),
                .stalkCursor
            ),
            (makeLocalSnapshot(interaction: .click, count: 2, escalation: 2), .swat),
            (makeLocalSnapshot(interaction: .keyboardActivity, count: 3, escalation: 3, typingPace: .steady), .coverEars),
            (
                makeLocalSnapshot(
                    interaction: .scroll,
                    count: 1,
                    escalation: 2,
                    motionEnergy: .quick
                ),
                .tumble
            )
        ]

        for (snapshot, expectedIntent) in cases {
            XCTAssertEqual(provider.immediateReaction(for: snapshot).intent, expectedIntent)
        }
    }

    func testAggregatorBucketsPointerMotionWithoutLeakingThePath() throws {
        var aggregator = InteractionAggregator()
        let start = Date(timeIntervalSince1970: 4_000)
        aggregator.reset(at: start)

        let snapshot = aggregator.record(
            InteractionSignal(
                kind: .mouseMovement,
                timestamp: start.addingTimeInterval(1),
                globalLocation: CGPoint(x: 913, y: 427),
                magnitude: 1_450,
                deltaX: -84,
                deltaY: 7
            ),
            characterState: "walk",
            displayIndex: 1,
            cursorRegion: .left
        )

        XCTAssertEqual(snapshot.motionEnergy, .frantic)
        XCTAssertEqual(snapshot.coarseDirection, .left)

        let encoded = String(data: try JSONEncoder().encode(snapshot), encoding: .utf8)!
        XCTAssertFalse(encoded.contains("913"))
        XCTAssertFalse(encoded.contains("427"))
        XCTAssertFalse(encoded.contains("-84"))
    }

    func testPersistentActivityPromptsForDoubleEscape() {
        let snapshot = ReactionSnapshot(
            interaction: .rapidClick,
            recentEventCounts: ["rapidClick": 12],
            interactionRate: .high,
            sessionDuration: .long,
            escalationLevel: 5,
            currentCharacterState: "angry",
            displayIndex: 1,
            cursorRegion: .bottomLeft
        )

        let plan = LocalReactionProvider().immediateReaction(for: snapshot)
        XCTAssertEqual(plan.intent, .promptDoubleEscape)
        XCTAssertEqual(plan.intensity, 1)
    }

    func testReactionPlanBoundsUntrustedNumbers() {
        let plan = ReactionPlan(intent: .bonk, intensity: 25, confidence: -4, source: .jev)
        XCTAssertEqual(plan.intensity, 1)
        XCTAssertEqual(plan.confidence, 0)
    }

    func testDialogueCatalogContainsHundredsOfStableOptions() {
        let catalog = DialogueCatalog.shared
        XCTAssertGreaterThanOrEqual(catalog.all.count, 300)
        XCTAssertEqual(Set(catalog.all.map(\.id)).count, catalog.all.count)

        for intent in ReactionIntent.allCases {
            XCTAssertTrue(catalog.all.contains { $0.intent == intent })
        }
    }

    func testTypingScaleIsBoundedIgnoresRepeatAndDecays() {
        var tracker = TypingScaleTracker()
        let start = Date(timeIntervalSinceReferenceDate: 10_000)
        var envelope = tracker.envelope

        for index in 0..<30 {
            envelope = tracker.record(
                InteractionSignal(
                    kind: .keyboardActivity,
                    timestamp: start.addingTimeInterval(Double(index) * 0.03)
                )
            )
        }

        XCTAssertEqual(envelope.peakScale, TypingScaleEnvelope.maximumScale, accuracy: 0.0001)
        let beforeRepeat = envelope
        envelope = tracker.record(
            InteractionSignal(
                kind: .keyboardActivity,
                timestamp: start.addingTimeInterval(1),
                isAutoRepeat: true
            )
        )
        XCTAssertEqual(envelope, beforeRepeat)

        let halfway = envelope.scale(
            at: envelope.decayStartsAt + (TypingScaleEnvelope.decayDuration / 2)
        )
        XCTAssertGreaterThan(halfway, 1)
        XCTAssertLessThan(halfway, TypingScaleEnvelope.maximumScale)
        XCTAssertEqual(
            envelope.scale(at: envelope.decayStartsAt + TypingScaleEnvelope.decayDuration + 1),
            1,
            accuracy: 0.0001
        )
    }

    func testJevProviderValidatesAndMapsTypedResponse() async throws {
        let provider = makeJevProvider()
        let snapshot = makeSnapshot()
        let dialogueID = try XCTUnwrap(
            DialogueCatalog.shared.shortlist(for: snapshot).first { $0.intent == .angry }?.id
        )
        MockURLProtocol.responseData = responseData(
            choice: "angry",
            confidence: 0.91,
            score: 3.5,
            dialogueID: dialogueID
        )

        let plan = try await provider.reaction(for: snapshot)

        XCTAssertEqual(plan.intent, .angry)
        XCTAssertEqual(plan.intensity, 0.875)
        XCTAssertEqual(plan.confidence, 0.91)
        XCTAssertEqual(plan.source, .jev)
        XCTAssertEqual(plan.tone, .smug)
        XCTAssertEqual(plan.pacing, .coolDown)
        XCTAssertEqual(plan.flourish, .shake)
        XCTAssertEqual(plan.dialogueID, dialogueID)

        let request = try provider.makeRequest(for: snapshot)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer unit-test-key")
        let body = String(data: request.httpBody!, encoding: .utf8)!
        XCTAssertTrue(body.contains("jev-1.13.0"))
        XCTAssertTrue(body.contains("\"dialogue\""))
        XCTAssertTrue(body.contains("\"typingPace\""))
        XCTAssertFalse(body.contains("unit-test-key"))
        XCTAssertFalse(body.lowercased().contains("keycode"))
    }

    func testJevProviderRejectsLowConfidenceResponse() async {
        MockURLProtocol.responseData = responseData(choice: "bonk", confidence: 0.2, score: 2)

        do {
            _ = try await makeJevProvider().reaction(for: makeSnapshot())
            XCTFail("Expected a low-confidence response to be rejected")
        } catch {
            XCTAssertEqual(error as? BonkError, .invalidJevResponse)
        }
    }

    func testJevProviderRejectsUnknownReaction() async {
        MockURLProtocol.responseData = responseData(choice: "eraseTheMac", confidence: 0.99, score: 4)

        do {
            _ = try await makeJevProvider().reaction(for: makeSnapshot())
            XCTFail("Expected an unknown reaction to be rejected")
        } catch {
            XCTAssertEqual(error as? BonkError, .invalidJevResponse)
        }
    }

    @MainActor
    func testJevRunsOnlyAfterTheQuietPeriod() async throws {
        let provider = RecordingReactionProvider()
        let director = JevDirectorMonitor()
        let character = CharacterEngine { false }
        let controller = ReactionController(
            characterEngine: character,
            director: director,
            quietPeriodNanoseconds: 80_000_000,
            providerFactory: { _ in provider },
            configuration: { (true, "unit-test-key") }
        )

        controller.beginSession()
        controller.handle(InteractionSignal(kind: .keyboardActivity))
        try await Task.sleep(nanoseconds: 35_000_000)
        let callsBeforeReset = await provider.calls
        XCTAssertEqual(callsBeforeReset, 0)

        controller.handle(InteractionSignal(kind: .keyboardActivity))
        try await Task.sleep(nanoseconds: 55_000_000)
        let callsDuringQuietPeriod = await provider.calls
        XCTAssertEqual(callsDuringQuietPeriod, 0)

        try await Task.sleep(nanoseconds: 55_000_000)
        let callsAfterQuietPeriod = await provider.calls
        XCTAssertEqual(callsAfterQuietPeriod, 1)
        XCTAssertEqual(director.requestCount, 1)
        controller.endSession()
    }

    func testContinuousMovementUsesOneGestureBeyondTheEventWindow() throws {
        var aggregator = InteractionAggregator()
        let start = Date(timeIntervalSince1970: 1_000)
        aggregator.reset(at: start.addingTimeInterval(-600))
        var snapshot: ReactionSnapshot!
        for index in 0...960 {
            snapshot = aggregator.record(
                InteractionSignal(kind: .mouseMovement, timestamp: start.addingTimeInterval(Double(index) / 120), magnitude: 100),
                characterState: "walk", displayIndex: nil, cursorRegion: .center
            )
            XCTAssertLessThanOrEqual(snapshot.escalationLevel, 2)
            XCTAssertEqual(snapshot.interactionRate, .low)
            XCTAssertNotEqual(LocalReactionProvider().immediateReaction(for: snapshot).intent, .promptDoubleEscape)
        }
        XCTAssertEqual(snapshot.recentEventCounts["mouseMovement"], 1)
        XCTAssertEqual(snapshot.movementGestureDuration, 8, accuracy: 0.001)
        XCTAssertEqual(LocalReactionProvider().immediateReaction(for: snapshot).intent, .stalkCursor)
        let encoded = try JSONEncoder().encode(snapshot)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("movementGestureDuration"))
        XCTAssertEqual(try JSONDecoder().decode(ReactionSnapshot.self, from: encoded).movementGestureDuration, 0)
    }

    func testSeparateMovementGesturesAreCountedButEscalationIsCapped() {
        var aggregator = InteractionAggregator(gestureGap: 0.1)
        let start = Date()
        aggregator.reset(at: start)
        var snapshot: ReactionSnapshot!
        for index in 0..<12 {
            snapshot = aggregator.record(
                InteractionSignal(kind: .mouseMovement, timestamp: start.addingTimeInterval(Double(index) * 0.2)),
                characterState: "walk", displayIndex: nil, cursorRegion: .center
            )
        }
        XCTAssertEqual(snapshot.recentEventCounts["mouseMovement"], 12)
        XCTAssertEqual(snapshot.escalationLevel, 2)
        XCTAssertEqual(snapshot.interactionRate, .low)
    }

    func testFirstFranticGesturePouncesAndTypingPaceSelectsIntent() {
        XCTAssertEqual(LocalReactionProvider().immediateReaction(for:
            makeLocalSnapshot(interaction: .mouseMovement, count: 1, escalation: 1, motionEnergy: .frantic)
        ).intent, .pounce)
        for (pace, expected) in [(TypingPace.slow, ReactionIntent.annoyed), (.steady, .coverEars), (.fast, .angry), (.frantic, .angry)] {
            XCTAssertEqual(LocalReactionProvider().immediateReaction(for:
                makeLocalSnapshot(interaction: .keyboardActivity, count: 1, escalation: 2, typingPace: pace)
            ).intent, expected)
        }
    }

    func testLocalProviderAvoidsConsecutiveIdenticalIntentToneBeats() {
        var aggregator = InteractionAggregator()
        let first = aggregator.record(InteractionSignal(kind: .keyboardActivity), characterState: "idle", displayIndex: nil, cursorRegion: .unknown)
        let plan = LocalReactionProvider().immediateReaction(for: first)
        let next = aggregator.record(
            InteractionSignal(kind: .keyboardActivity), characterState: "annoyed", displayIndex: nil,
            cursorRegion: .unknown, recentCharacterBeats: ["\(plan.intent.rawValue)|\(plan.tone.rawValue)|sustain"]
        )
        let second = LocalReactionProvider().immediateReaction(for: next)
        XCTAssertEqual(second.intent, plan.intent)
        XCTAssertNotEqual(second.tone, plan.tone)
    }

    @MainActor
    func testMovementAndScrollRespectBothDeadlinesIncludingExactBoundary() {
        let (controller, character) = makeLocalController()
        defer { controller.endSession() }
        let start = Date()
        controller.handle(InteractionSignal(kind: .mouseMovement, timestamp: start))
        let first = character.presentation
        controller.handle(InteractionSignal(kind: .mouseMovement, timestamp: start.addingTimeInterval(1), magnitude: 1_500))
        controller.handle(InteractionSignal(kind: .scroll, timestamp: start.addingTimeInterval(2), magnitude: 20))
        XCTAssertEqual(character.presentation.state, first.state)
        XCTAssertEqual(character.presentation.message, first.message)
        XCTAssertEqual(character.presentation.variant, first.variant)
        controller.handle(InteractionSignal(kind: .keyboardActivity, timestamp: start.addingTimeInterval(3)))
        XCTAssertEqual(character.presentation.state, .annoyed)
        XCTAssertEqual(character.presentation.message, first.message)
        let keyVariant = character.presentation.variant
        controller.handle(InteractionSignal(kind: .mouseMovement, timestamp: start.addingTimeInterval(4), magnitude: 1_500))
        XCTAssertEqual(character.presentation.variant, keyVariant)
        controller.handle(InteractionSignal(kind: .mouseMovement, timestamp: start.addingTimeInterval(7), magnitude: 1_500))
        XCTAssertEqual(character.presentation.state, .pounce)
        XCTAssertGreaterThan(character.presentation.variant, keyVariant)
        XCTAssertNotEqual(character.presentation.message, first.message)
    }

    @MainActor
    func testAllDeliberateInputsRestartThePoseButPreserveYoungText() {
        let (controller, character) = makeLocalController()
        defer { controller.endSession() }
        let start = Date()
        controller.handle(InteractionSignal(kind: .mouseMovement, timestamp: start))
        let text = character.presentation.message
        for (index, kind) in [InteractionKind.click, .rapidClick, .keyboardActivity, .keyboardActivity, .shortcutAttempt].enumerated() {
            let variant = character.presentation.variant
            controller.handle(InteractionSignal(kind: kind, timestamp: start.addingTimeInterval(Double(index + 1) * 0.1)))
            XCTAssertGreaterThan(character.presentation.variant, variant)
            XCTAssertEqual(character.presentation.message, text)
        }
    }

    @MainActor
    func testPointerKeepsUpdatingWhileCharacterPositionAndDisplayHold() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let (controller, character) = makeLocalController()
        defer { controller.endSession() }
        let start = Date()
        controller.handle(InteractionSignal(kind: .mouseMovement, timestamp: start))
        let first = character.presentation
        let point = CGPoint(x: screen.frame.midX, y: screen.frame.midY)
        controller.handle(InteractionSignal(kind: .mouseMovement, timestamp: start.addingTimeInterval(1), globalLocation: point, deltaX: -10))
        XCTAssertEqual(character.presentation.position, first.position)
        XCTAssertEqual(character.presentation.activeDisplayNumber, first.activeDisplayNumber)
        XCTAssertNotNil(character.cursorPresentation.activeDisplayNumber)
        XCTAssertNotNil(character.cursorPresentation.position)
        XCTAssertNotEqual(character.presentation.lookX, first.lookX)
        XCTAssertEqual(character.presentation.facing, -1)
        controller.handle(InteractionSignal(kind: .mouseMovement, timestamp: start.addingTimeInterval(4), globalLocation: point))
        XCTAssertNotEqual(character.presentation.position, first.position)
        XCTAssertEqual(character.presentation.activeDisplayNumber, character.cursorPresentation.activeDisplayNumber)
    }

    @MainActor
    func testStateOnlyApplicationDoesNotConsumeUnpublishedDialogue() throws {
        let character = CharacterEngine { false }
        let line = try XCTUnwrap(DialogueCatalog.shared.all.first { $0.intent == .bonk })
        let plan = ReactionPlan(intent: .bonk, intensity: 0.5, confidence: 1, source: .local, dialogueID: line.id)
        character.apply(plan, near: nil, preservingMessage: true)
        XCTAssertNil(character.presentation.message)
        let pose = character.presentation
        character.publishMessage(for: plan)
        XCTAssertEqual(character.presentation.message, line.text)
        XCTAssertEqual(character.presentation.variant, pose.variant)
        XCTAssertEqual(character.presentation.reactionStartedAt, pose.reactionStartedAt)
        XCTAssertEqual(character.presentation.state, pose.state)
    }

    @MainActor
    func testLoneClickPublishesTextAtDeadlineWithoutReplayingAnimation() async throws {
        let (controller, character) = makeLocalController(displayInterval: 0.12)
        defer { controller.endSession() }
        controller.handle(InteractionSignal(kind: .mouseMovement))
        let original = character.presentation.message
        try await Task.sleep(nanoseconds: 30_000_000)
        controller.handle(InteractionSignal(kind: .click))
        let pose = character.presentation
        XCTAssertEqual(pose.state, .bonk)
        XCTAssertEqual(pose.message, original)
        try await Task.sleep(nanoseconds: 130_000_000)
        XCTAssertTrue(DialogueCatalog.shared.all.contains { $0.intent == .bonk && $0.text == character.presentation.message })
        XCTAssertEqual(character.presentation.variant, pose.variant)
        XCTAssertEqual(character.presentation.reactionStartedAt, pose.reactionStartedAt)
        let published = character.presentation
        controller.handle(InteractionSignal(kind: .mouseMovement, magnitude: 1_500))
        XCTAssertEqual(character.presentation.variant, published.variant)
        XCTAssertEqual(character.presentation.message, published.message)
    }

    @MainActor
    func testLatestPendingCandidateWinsAndFresherPublicationCancelsOldOne() async throws {
        let (controller, character) = makeLocalController(displayInterval: 0.1)
        defer { controller.endSession() }
        let start = Date()
        controller.handle(InteractionSignal(kind: .mouseMovement, timestamp: start))
        controller.handle(InteractionSignal(kind: .click, timestamp: start.addingTimeInterval(0.01)))
        controller.handle(InteractionSignal(kind: .click, timestamp: start.addingTimeInterval(0.02)))
        try await Task.sleep(nanoseconds: 130_000_000)
        XCTAssertTrue(DialogueCatalog.shared.all.contains { $0.intent == .swat && $0.text == character.presentation.message })
        controller.handle(InteractionSignal(kind: .keyboardActivity))
        controller.handle(InteractionSignal(kind: .scroll, timestamp: Date().addingTimeInterval(1), magnitude: 20))
        let fresh = character.presentation
        try await Task.sleep(nanoseconds: 130_000_000)
        XCTAssertEqual(character.presentation, fresh)
    }

    @MainActor
    func testRestWaitsForReadingWindowAndFirstMovementWakesGently() async throws {
        let (controller, character) = makeLocalController(displayInterval: 0.1, restInterval: 0.02)
        defer { controller.endSession() }
        controller.handle(InteractionSignal(kind: .mouseMovement))
        try await Task.sleep(nanoseconds: 45_000_000)
        XCTAssertNotNil(character.presentation.message)
        XCTAssertNotEqual(character.presentation.state, .sleeping)
        try await Task.sleep(nanoseconds: 90_000_000)
        XCTAssertEqual(character.presentation.state, .sleeping)
        XCTAssertNil(character.presentation.message)
        XCTAssertEqual(character.presentation.tone, .sleepy)
        controller.handle(InteractionSignal(kind: .mouseMovement))
        XCTAssertEqual(character.presentation.state, .notice)
        XCTAssertNotNil(character.presentation.message)
        XCTAssertLessThanOrEqual(character.presentation.intensity, 0.4)
    }

    @MainActor
    func testDuePendingMessageReceivesReadingTimeBeforeRest() async throws {
        let (controller, character) = makeLocalController(displayInterval: 0.1, restInterval: 0.01)
        defer { controller.endSession() }
        controller.handle(InteractionSignal(kind: .mouseMovement))
        controller.handle(InteractionSignal(kind: .click))
        try await Task.sleep(nanoseconds: 130_000_000)
        XCTAssertEqual(character.presentation.state, .bonk)
        XCTAssertTrue(DialogueCatalog.shared.all.contains { $0.intent == .bonk && $0.text == character.presentation.message })
        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(character.presentation.state, .sleeping)
        XCTAssertNil(character.presentation.message)
    }

    @MainActor
    func testEndSessionCancelsTimersAndRepeatedBeginStartsClean() async throws {
        let (controller, character) = makeLocalController(displayInterval: 0.08, restInterval: 0.12)
        controller.handle(InteractionSignal(kind: .mouseMovement))
        controller.handle(InteractionSignal(kind: .click))
        controller.endSession()
        let stopped = character.presentation
        try await Task.sleep(nanoseconds: 180_000_000)
        XCTAssertEqual(character.presentation, stopped)
        for _ in 0..<3 {
            controller.beginSession()
            controller.handle(InteractionSignal(kind: .mouseMovement))
            XCTAssertEqual(character.presentation.state, .notice)
            controller.handle(InteractionSignal(kind: .click))
        }
        controller.beginSession()
        defer { controller.endSession() }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(character.presentation.message)
        controller.handle(InteractionSignal(kind: .mouseMovement))
        XCTAssertEqual(character.presentation.state, .notice)
    }

    @MainActor
    func testJevTextWaitsForReadingWindowAndDoesNotReplayPose() async throws {
        let provider = RecordingReactionProvider()
        let director = JevDirectorMonitor()
        let character = CharacterEngine { false }
        let controller = ReactionController(characterEngine: character, director: director,
            quietPeriodNanoseconds: 10_000_000, displayInterval: 0.15,
            providerFactory: { _ in provider }, configuration: { (true, "unit-test-key") })
        controller.beginSession()
        defer { controller.endSession() }
        controller.handle(InteractionSignal(kind: .click))
        let local = character.presentation
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(character.presentation.message, local.message)
        XCTAssertEqual(character.presentation.variant, local.variant)
        XCTAssertEqual(director.phase, .directing)
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(director.phase, .applied)
        XCTAssertTrue(DialogueCatalog.shared.all.contains { $0.intent == .coverEars && $0.text == character.presentation.message })
        XCTAssertEqual(character.presentation.variant, local.variant)
    }

    @MainActor
    func testLateJevResultIsDiscardedAfterRest() async throws {
        let provider = HeldReactionProvider()
        let character = CharacterEngine { false }
        let controller = ReactionController(characterEngine: character, director: JevDirectorMonitor(),
            quietPeriodNanoseconds: 1_000_000, displayInterval: 0.02, restInterval: 0.05,
            providerFactory: { _ in provider }, configuration: { (true, "unit-test-key") })
        controller.beginSession()
        defer { controller.endSession() }
        controller.handle(InteractionSignal(kind: .click))
        try await waitForRequest(provider)
        try await Task.sleep(nanoseconds: 90_000_000)
        XCTAssertEqual(character.presentation.state, .sleeping)
        let sleeping = character.presentation
        await provider.releaseAll()
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(character.presentation, sleeping)
    }

    @MainActor
    func testNewInputAndAuthenticationInvalidateInFlightJevResults() async throws {
        for authenticating in [false, true] {
            let provider = HeldReactionProvider()
            let character = CharacterEngine { false }
            let controller = ReactionController(characterEngine: character, director: JevDirectorMonitor(),
                quietPeriodNanoseconds: 1_000_000, displayInterval: 0.06,
                providerFactory: { _ in provider }, configuration: { (true, "unit-test-key") })
            controller.beginSession()
            controller.handle(InteractionSignal(kind: .click))
            try await waitForRequest(provider)
            if authenticating {
                controller.pointToAuthentication()
            } else {
                controller.handle(InteractionSignal(kind: .keyboardActivity))
            }
            await provider.releaseAll()
            try await Task.sleep(nanoseconds: 100_000_000)
            XCTAssertNotEqual(character.presentation.state, .angry)
            if authenticating {
                XCTAssertEqual(character.presentation.message, "Double Esc captured. Use Touch ID.")
            } else {
                XCTAssertTrue(DialogueCatalog.shared.all.contains { $0.intent == .annoyed && $0.text == character.presentation.message })
            }
            controller.endSession()
            await provider.releaseAll()
        }
    }

    @MainActor
    func testNewSignalInvalidatesQueuedJevTextAndSessionEndDiscardsLateReply() async throws {
        let provider = HeldReactionProvider()
        let director = JevDirectorMonitor()
        let character = CharacterEngine { false }
        let controller = ReactionController(characterEngine: character, director: director,
            quietPeriodNanoseconds: 1_000_000, displayInterval: 0.1,
            providerFactory: { _ in provider }, configuration: { (true, "unit-test-key") })
        controller.beginSession()
        controller.handle(InteractionSignal(kind: .click))
        let local = character.presentation.message
        try await waitForRequest(provider)
        await provider.releaseAll()
        try await Task.sleep(nanoseconds: 15_000_000)
        controller.handle(InteractionSignal(kind: .mouseMovement))
        try await Task.sleep(nanoseconds: 130_000_000)
        XCTAssertEqual(character.presentation.message, local)
        controller.endSession()
        let ended = character.presentation
        await provider.releaseAll()
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(character.presentation, ended)
        XCTAssertEqual(director.phase, .localOnly)
    }

    @MainActor
    func testQueuedJevKeepsClickDialogueWhenInvalidatedOrDisabled() async throws {
        for disableJev in [false, true] {
            var enabled = true
            let provider = HeldReactionProvider()
            let character = CharacterEngine { false }
            let controller = ReactionController(characterEngine: character, director: JevDirectorMonitor(),
                quietPeriodNanoseconds: 1_000_000, displayInterval: 0.15,
                providerFactory: { _ in provider }, configuration: { (enabled, "unit-test-key") })
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
            XCTAssertEqual(character.presentation.state, .bonk)
            XCTAssertTrue(DialogueCatalog.shared.all.contains { $0.intent == .bonk && $0.text == character.presentation.message })
            controller.endSession()
            await provider.releaseAll()
        }
    }

    private func waitForRequest(_ provider: HeldReactionProvider) async throws {
        for _ in 0..<100 {
            if await provider.calls > 0 { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Jev request did not start")
        throw BonkError.jevUnavailable
    }

    @MainActor
    private func makeLocalController(displayInterval: TimeInterval = 4, restInterval: TimeInterval = 20) -> (ReactionController, CharacterEngine) {
        let character = CharacterEngine { false }
        let controller = ReactionController(characterEngine: character, director: JevDirectorMonitor(),
            displayInterval: displayInterval, restInterval: restInterval, configuration: { (false, nil) })
        controller.beginSession()
        return (controller, character)
    }

    private func makeJevProvider() -> JevReactionProvider {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return JevReactionProvider(
            apiKey: "unit-test-key",
            endpoint: URL(string: "https://example.invalid/v1/systemone")!,
            session: URLSession(configuration: configuration)
        )
    }

    private func makeSnapshot() -> ReactionSnapshot {
        ReactionSnapshot(
            interaction: .rapidClick,
            recentEventCounts: ["rapidClick": 8],
            interactionRate: .high,
            sessionDuration: .short,
            escalationLevel: 4,
            currentCharacterState: "annoyed",
            displayIndex: 0,
            cursorRegion: .right
        )
    }

    private func makeLocalSnapshot(
        interaction: InteractionKind,
        count: Int,
        escalation: Int,
        motionEnergy: MotionEnergy = .still,
        typingPace: TypingPace = .none
    ) -> ReactionSnapshot {
        ReactionSnapshot(
            interaction: interaction,
            recentEventCounts: [interaction.rawValue: count],
            interactionRate: count >= 5 ? .high : .medium,
            sessionDuration: .short,
            escalationLevel: escalation,
            currentCharacterState: "idle",
            displayIndex: 0,
            cursorRegion: .center,
            motionEnergy: motionEnergy,
            typingPace: typingPace
        )
    }

    private func responseData(
        choice: String,
        confidence: Double,
        score: Double,
        dialogueID: String = "not-a-candidate"
    ) -> Data {
        Data(
            """
            {
              "model": "jev-1.13.0",
              "answers": {
                "reaction": {
                  "type": "choice",
                  "choice": "\(choice)",
                  "confidence": \(confidence),
                  "probabilities": { "\(choice)": 1.0 }
                },
                "intensity": {
                  "type": "score",
                  "score": \(score),
                  "confidence": 0.9,
                  "legend": { "0": "low", "4": "high" },
                  "probabilities": { "4": 1.0 }
                },
                "tone": {
                  "type": "choice",
                  "choice": "smug",
                  "confidence": 0.9,
                  "probabilities": { "smug": 1.0 }
                },
                "pacing": {
                  "type": "choice",
                  "choice": "coolDown",
                  "confidence": 0.9,
                  "probabilities": { "coolDown": 1.0 }
                },
                "flourish": {
                  "type": "choice",
                  "choice": "shake",
                  "confidence": 0.9,
                  "probabilities": { "shake": 1.0 }
                },
                "dialogue": {
                  "type": "choice",
                  "choice": "\(dialogueID)",
                  "confidence": 0.9,
                  "probabilities": { "\(dialogueID)": 1.0 }
                }
              },
              "usage": { "input_tokens": 50, "output_tokens": 10 }
            }
            """.utf8
        )
    }
}

private actor RecordingReactionProvider: ReactionProvider {
    private(set) var calls = 0

    func reaction(for snapshot: ReactionSnapshot) async throws -> ReactionPlan {
        calls += 1
        return ReactionPlan(
            intent: .coverEars,
            intensity: 0.5,
            confidence: 0.9,
            source: .jev,
            tone: .playful,
            pacing: .coolDown,
            flourish: .pose
        )
    }
}

private final class MockURLProtocol: URLProtocol {
    static var responseData = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private actor HeldReactionProvider: ReactionProvider {
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
