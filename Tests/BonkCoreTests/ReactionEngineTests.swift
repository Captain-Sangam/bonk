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
            (makeLocalSnapshot(interaction: .keyboardActivity, count: 3, escalation: 3), .coverEars),
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
        motionEnergy: MotionEnergy = .still
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
            motionEnergy: motionEnergy
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
