import BonkCore
import Foundation

private enum CheckFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message): return message
        }
    }
}

private final class MockURLProtocol: URLProtocol {
    static var responseData = Data()
    static var observedRequestBody = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.observedRequestBody = request.httpBody ?? Data()
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

@main
private struct BonkChecks {
    static func main() async {
        do {
            try await runChecks()
            print("Bonk checks passed")
        } catch {
            fputs("Bonk checks failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func runChecks() async throws {
        try require(BonkBrandAssets.foxLogo != nil, "Fox logo resource could not be loaded")
        try require(BonkBrandAssets.appIcon != nil, "App icon resource could not be loaded")
        try require(
            BonkBrandAssets.menuBarLogo?.size == NSSize(width: 18, height: 18),
            "Menu-bar logo must use an 18-point intrinsic size"
        )

        var aggregator = InteractionAggregator()
        let start = Date(timeIntervalSince1970: 1_000)
        aggregator.reset(at: start)

        let snapshot = aggregator.record(
            InteractionSignal(
                kind: .rapidClick,
                timestamp: start.addingTimeInterval(1),
                globalLocation: CGPoint(x: 987, y: 654)
            ),
            characterState: "bonk",
            displayIndex: 0,
            cursorRegion: .right
        )

        let encoded = String(data: try JSONEncoder().encode(snapshot), encoding: .utf8)!
        try require(!encoded.contains("987") && !encoded.contains("654"), "Precise pointer coordinates leaked into reaction state")
        try require(!encoded.lowercased().contains("keycode"), "Key content leaked into reaction state")

        let local = LocalReactionProvider().immediateReaction(for: snapshot)
        try require(local.intent == .repeatBonk, "Rapid clicking did not map to repeatBonk")
        try require(local.source == .local, "Local fallback was not marked local")

        MockURLProtocol.responseData = Data(
            """
            {
              "model": "jev-1.13.0",
              "answers": {
                "reaction": {
                  "type": "choice",
                  "choice": "angry",
                  "confidence": 0.91,
                  "probabilities": { "angry": 0.91, "repeatBonk": 0.09 }
                },
                "intensity": {
                  "type": "score",
                  "score": 3.5,
                  "confidence": 0.88,
                  "legend": { "0": "low", "4": "high" },
                  "probabilities": { "3": 0.5, "4": 0.5 }
                },
                "tone": {
                  "type": "choice",
                  "choice": "dramatic",
                  "confidence": 0.86,
                  "probabilities": { "dramatic": 0.86, "playful": 0.14 }
                },
                "pacing": {
                  "type": "choice",
                  "choice": "escalate",
                  "confidence": 0.82,
                  "probabilities": { "escalate": 0.82, "sustain": 0.18 }
                },
                "flourish": {
                  "type": "choice",
                  "choice": "shake",
                  "confidence": 0.84,
                  "probabilities": { "shake": 0.84, "none": 0.16 }
                },
                "dialogue": {
                  "type": "choice",
                  "choice": "not-a-candidate",
                  "confidence": 0.75,
                  "probabilities": { "not-a-candidate": 1.0 }
                }
              },
              "usage": { "input_tokens": 100, "output_tokens": 10 }
            }
            """.utf8
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let jev = JevReactionProvider(
            apiKey: "test-key",
            endpoint: URL(string: "https://example.invalid/v1/systemone")!,
            session: session
        )
        let remote = try await jev.reaction(for: snapshot)

        try require(remote.intent == .angry, "Jev choice did not map to a known reaction")
        try require(remote.source == .jev, "Jev reaction was not marked remote")
        try require(remote.intensity == 0.875, "Jev intensity was not normalized")
        try require(remote.tone == .dramatic, "Jev tone was not applied")
        try require(remote.pacing == .escalate, "Jev pacing was not applied")
        try require(remote.flourish == .shake, "Jev flourish was not applied")
        try require(BonkDialogueMetrics.optionCount >= 300, "Dialogue catalog did not contain hundreds of options")

        let outboundRequest = try jev.makeRequest(for: snapshot)
        let body = String(data: outboundRequest.httpBody ?? Data(), encoding: .utf8)!
        try require(body.contains("jev-1.13.0"), "Jev request did not pin the model version")
        try require(body.contains("\"dialogue\""), "Jev request did not include dialogue direction")
        try require(body.contains("\"typingPace\""), "Jev request did not include a coarse typing pace")
        try require(!body.lowercased().contains("keycode"), "Jev request included key content")
        try require(!body.contains("test-key"), "API key leaked into request body")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CheckFailure.failed(message) }
    }
}
