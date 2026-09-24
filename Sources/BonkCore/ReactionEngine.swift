import Foundation

public protocol ReactionProvider: Sendable {
    func reaction(for snapshot: ReactionSnapshot) async throws -> ReactionPlan
}

public struct InteractionAggregator: Sendable {
    private var sessionStartedAt = Date()
    private var events: [(date: Date, kind: InteractionKind)] = []

    public init() {}

    public mutating func reset(at date: Date = Date()) {
        sessionStartedAt = date
        events.removeAll(keepingCapacity: true)
    }

    public mutating func record(
        _ signal: InteractionSignal,
        characterState: String,
        displayIndex: Int?,
        cursorRegion: CoarseCursorRegion
    ) -> ReactionSnapshot {
        events.append((signal.timestamp, signal.kind))
        let cutoff = signal.timestamp.addingTimeInterval(-5)
        events.removeAll { $0.date < cutoff }

        var counts: [String: Int] = [:]
        for event in events {
            counts[event.kind.rawValue, default: 0] += 1
        }

        let rate: InteractionRate
        switch events.count {
        case 0...2: rate = .low
        case 3...7: rate = .medium
        default: rate = .high
        }

        let elapsed = signal.timestamp.timeIntervalSince(sessionStartedAt)
        let duration: SessionDurationBucket
        switch elapsed {
        case ..<10: duration = .justStarted
        case ..<60: duration = .short
        case ..<300: duration = .established
        default: duration = .long
        }

        let escalation: Int
        switch events.count {
        case 0: escalation = 0
        case 1: escalation = signal.kind == .mouseMovement ? 1 : 2
        case 2...3: escalation = 2
        case 4...6: escalation = 3
        case 7...10: escalation = 4
        default: escalation = 5
        }

        return ReactionSnapshot(
            interaction: signal.kind,
            recentEventCounts: counts,
            interactionRate: rate,
            sessionDuration: duration,
            escalationLevel: escalation,
            currentCharacterState: characterState,
            displayIndex: displayIndex,
            cursorRegion: cursorRegion
        )
    }
}

public struct LocalReactionProvider: ReactionProvider {
    public init() {}

    public func reaction(for snapshot: ReactionSnapshot) async throws -> ReactionPlan {
        ReactionPlan(
            intent: intent(for: snapshot),
            intensity: Double(snapshot.escalationLevel) / 5,
            confidence: 1,
            source: .local
        )
    }

    public func immediateReaction(for snapshot: ReactionSnapshot) -> ReactionPlan {
        ReactionPlan(
            intent: intent(for: snapshot),
            intensity: Double(snapshot.escalationLevel) / 5,
            confidence: 1,
            source: .local
        )
    }

    private func intent(for snapshot: ReactionSnapshot) -> ReactionIntent {
        if snapshot.escalationLevel >= 5 {
            return .pointToTouchID
        }

        switch snapshot.interaction {
        case .mouseMovement:
            return snapshot.escalationLevel <= 1 ? .notice : .followCursor
        case .click:
            let clickCount = snapshot.recentEventCounts[InteractionKind.click.rawValue, default: 0]
            return clickCount >= 3 ? .repeatBonk : .bonk
        case .rapidClick:
            return snapshot.escalationLevel >= 4 ? .angry : .repeatBonk
        case .keyboardActivity:
            return snapshot.escalationLevel >= 4 ? .angry : .annoyed
        case .scroll:
            return .tumble
        case .shortcutAttempt:
            return .blockShortcut
        }
    }
}

public struct JevReactionProvider: ReactionProvider {
    public static let defaultEndpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!
    public static let pinnedModel = "jev-1.13.0"

    private let apiKey: String
    private let endpoint: URL
    private let session: URLSession
    private let minimumConfidence: Double

    public init(
        apiKey: String,
        endpoint: URL = Self.defaultEndpoint,
        minimumConfidence: Double = 0.55,
        timeout: TimeInterval = 1.5,
        session injectedSession: URLSession? = nil
    ) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.minimumConfidence = minimumConfidence
        if let injectedSession {
            session = injectedSession
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = timeout
            configuration.timeoutIntervalForResource = timeout
            configuration.waitsForConnectivity = false
            session = URLSession(configuration: configuration)
        }
    }

    public func reaction(for snapshot: ReactionSnapshot) async throws -> ReactionPlan {
        let request = try makeRequest(for: snapshot)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw BonkError.jevUnavailable
        }

        let decoded = try JSONDecoder().decode(JevResponse.self, from: data)
        guard decoded.answers.reaction.confidence >= minimumConfidence,
              let intent = ReactionIntent(rawValue: decoded.answers.reaction.choice)
        else {
            throw BonkError.invalidJevResponse
        }

        let maximumScore = 4.0
        return ReactionPlan(
            intent: intent,
            intensity: decoded.answers.intensity.score / maximumScore,
            confidence: decoded.answers.reaction.confidence,
            source: .jev
        )
    }

    public func makeRequest(for snapshot: ReactionSnapshot) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(JevRequest(state: snapshot))
        return request
    }
}

private struct JevRequest: Encodable {
    let state: ReactionSnapshot
    let model = JevReactionProvider.pinnedModel
    let questions = Questions()

    struct Questions: Encodable {
        let reaction = ChoiceQuestion(
            type: "choice",
            instructions: "Choose the single best playful character reaction for the current guarded Mac interaction. Prefer variety, respect escalation, and use pointToTouchID for persistent attempts.",
            criteria: [
                "notice": "Wake and acknowledge gentle first movement.",
                "followCursor": "Track continuing pointer movement.",
                "bonk": "Respond to a click with the primary bonk gag.",
                "repeatBonk": "Respond to repeated or rapid clicking.",
                "annoyed": "Show mild frustration at continued keyboard activity.",
                "angry": "Show dramatic frustration at persistent high-rate activity.",
                "blockShortcut": "Hold up a stop sign for a shortcut attempt.",
                "tumble": "Get pushed or tumble in response to scrolling.",
                "pointToTouchID": "Direct a persistent user to owner authentication."
            ]
        )

        let intensity = ScoreQuestion(
            type: "score",
            instructions: "Rate how intense the character reaction should be.",
            criteria: [
                "Barely react.",
                "Notice without annoyance.",
                "Playful standard reaction.",
                "Clearly annoyed.",
                "Maximum dramatic reaction."
            ]
        )
    }

    struct ChoiceQuestion: Encodable {
        let type: String
        let instructions: String
        let criteria: [String: String]
    }

    struct ScoreQuestion: Encodable {
        let type: String
        let instructions: String
        let criteria: [String]
    }
}

private struct JevResponse: Decodable {
    let answers: Answers

    struct Answers: Decodable {
        let reaction: ChoiceAnswer
        let intensity: ScoreAnswer
    }

    struct ChoiceAnswer: Decodable {
        let choice: String
        let confidence: Double
    }

    struct ScoreAnswer: Decodable {
        let score: Double
        let confidence: Double
    }
}
