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
            .scroll: .tumble,
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

    func testPersistentActivityAlwaysPointsToAuthentication() {
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
        XCTAssertEqual(plan.intent, .pointToTouchID)
        XCTAssertEqual(plan.intensity, 1)
    }

    func testReactionPlanBoundsUntrustedNumbers() {
        let plan = ReactionPlan(intent: .bonk, intensity: 25, confidence: -4, source: .jev)
        XCTAssertEqual(plan.intensity, 1)
        XCTAssertEqual(plan.confidence, 0)
    }

    func testJevProviderValidatesAndMapsTypedResponse() async throws {
        MockURLProtocol.responseData = responseData(choice: "angry", confidence: 0.91, score: 3.5)
        let provider = makeJevProvider()
        let snapshot = makeSnapshot()

        let plan = try await provider.reaction(for: snapshot)

        XCTAssertEqual(plan.intent, .angry)
        XCTAssertEqual(plan.intensity, 0.875)
        XCTAssertEqual(plan.confidence, 0.91)
        XCTAssertEqual(plan.source, .jev)

        let request = try provider.makeRequest(for: snapshot)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer unit-test-key")
        let body = String(data: request.httpBody!, encoding: .utf8)!
        XCTAssertTrue(body.contains("jev-1.13.0"))
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

    private func responseData(choice: String, confidence: Double, score: Double) -> Data {
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
                }
              },
              "usage": { "input_tokens": 50, "output_tokens": 10 }
            }
            """.utf8
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
