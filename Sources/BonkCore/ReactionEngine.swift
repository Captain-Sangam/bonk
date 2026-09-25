import Foundation

public protocol ReactionProvider: Sendable {
    func reaction(for snapshot: ReactionSnapshot) async throws -> ReactionPlan
}

public struct InteractionAggregator: Sendable {
    private var sessionStartedAt = Date()
    private var events: [(date: Date, kind: InteractionKind)] = []
    private var typingEvents: [Date] = []

    public init() {}

    public mutating func reset(at date: Date = Date()) {
        sessionStartedAt = date
        events.removeAll(keepingCapacity: true)
        typingEvents.removeAll(keepingCapacity: true)
    }

    public mutating func record(
        _ signal: InteractionSignal,
        characterState: String,
        displayIndex: Int?,
        cursorRegion: CoarseCursorRegion,
        recentCharacterBeats: [String] = []
    ) -> ReactionSnapshot {
        if !signal.isAutoRepeat {
            events.append((signal.timestamp, signal.kind))
        }
        let cutoff = signal.timestamp.addingTimeInterval(-5)
        events.removeAll { $0.date < cutoff }

        if (signal.kind == .keyboardActivity || signal.kind == .shortcutAttempt), !signal.isAutoRepeat {
            typingEvents.append(signal.timestamp)
        }
        let typingCutoff = signal.timestamp.addingTimeInterval(-TypingScaleTracker.rollingWindow)
        typingEvents.removeAll { $0 < typingCutoff }

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
            cursorRegion: cursorRegion,
            motionEnergy: Self.motionEnergy(for: signal),
            coarseDirection: Self.coarseDirection(for: signal),
            typingPace: Self.typingPace(for: typingEvents.count),
            recentCharacterBeats: recentCharacterBeats
        )
    }

    private static func typingPace(for count: Int) -> TypingPace {
        switch count {
        case 0: return .none
        case 1...2: return .slow
        case 3...5: return .steady
        case 6...9: return .fast
        default: return .frantic
        }
    }

    private static func motionEnergy(for signal: InteractionSignal) -> MotionEnergy {
        switch signal.kind {
        case .mouseMovement:
            switch signal.magnitude {
            case ..<40: return .still
            case ..<450: return .gentle
            case ..<1_100: return .quick
            default: return .frantic
            }
        case .scroll:
            switch signal.magnitude {
            case ..<1: return .still
            case ..<5: return .gentle
            case ..<18: return .quick
            default: return .frantic
            }
        default:
            return .still
        }
    }

    private static func coarseDirection(for signal: InteractionSignal) -> CoarseDirection {
        guard abs(signal.deltaX) >= 0.5 || abs(signal.deltaY) >= 0.5 else {
            return .stationary
        }
        if abs(signal.deltaX) > abs(signal.deltaY) {
            return signal.deltaX < 0 ? .left : .right
        }
        return signal.deltaY < 0 ? .down : .up
    }
}

public struct LocalReactionProvider: ReactionProvider {
    public init() {}

    public func reaction(for snapshot: ReactionSnapshot) async throws -> ReactionPlan {
        immediateReaction(for: snapshot)
    }

    public func immediateReaction(for snapshot: ReactionSnapshot) -> ReactionPlan {
        let intent = intent(for: snapshot)
        return ReactionPlan(
            intent: intent,
            intensity: Double(snapshot.escalationLevel) / 5,
            confidence: 1,
            source: .local,
            tone: localTone(for: snapshot),
            pacing: snapshot.escalationLevel >= 4 ? .escalate : .sustain,
            flourish: localFlourish(for: intent)
        )
    }

    private func localTone(for snapshot: ReactionSnapshot) -> ReactionTone {
        if snapshot.sessionDuration == .justStarted { return .sleepy }
        if snapshot.escalationLevel >= 4 { return .dramatic }
        switch snapshot.interaction {
        case .keyboardActivity: return .grumpy
        case .shortcutAttempt: return .smug
        default: return .playful
        }
    }

    private func localFlourish(for intent: ReactionIntent) -> ReactionFlourish {
        switch intent {
        case .pounce: return .hop
        case .angry: return .shake
        case .tumble: return .spin
        case .bonk, .repeatBonk, .swat, .blockShortcut: return .pose
        default: return .none
        }
    }

    private func intent(for snapshot: ReactionSnapshot) -> ReactionIntent {
        if snapshot.escalationLevel >= 5, snapshot.sessionDuration == .long {
            return .promptDoubleEscape
        }

        switch snapshot.interaction {
        case .mouseMovement:
            let movementCount = snapshot.recentEventCounts[InteractionKind.mouseMovement.rawValue, default: 0]
            if movementCount <= 1 { return .notice }
            if snapshot.motionEnergy == .frantic { return .pounce }
            if movementCount >= 5 { return .stalkCursor }
            return .followCursor
        case .click:
            let clickCount = snapshot.recentEventCounts[InteractionKind.click.rawValue, default: 0]
            if clickCount == 2 { return .swat }
            return clickCount >= 3 ? .repeatBonk : .bonk
        case .rapidClick:
            return snapshot.escalationLevel >= 4 ? .angry : .repeatBonk
        case .keyboardActivity:
            let keyCount = snapshot.recentEventCounts[InteractionKind.keyboardActivity.rawValue, default: 0]
            if snapshot.escalationLevel >= 4 { return .angry }
            return keyCount >= 2 ? .coverEars : .annoyed
        case .scroll:
            return snapshot.motionEnergy == .quick || snapshot.motionEnergy == .frantic ? .tumble : .cling
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
    private let stylingConfidence: Double

    public init(
        apiKey: String,
        endpoint: URL = Self.defaultEndpoint,
        minimumConfidence: Double = 0.60,
        stylingConfidence: Double = 0.50,
        timeout: TimeInterval = 1.5,
        session injectedSession: URLSession? = nil
    ) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.minimumConfidence = minimumConfidence
        self.stylingConfidence = stylingConfidence
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
        let candidates = DialogueCatalog.shared.shortlist(for: snapshot)
        let request = try makeRequest(for: snapshot, candidates: candidates)
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

        let tone = decoded.answers.tone.confidence >= stylingConfidence
            ? ReactionTone(rawValue: decoded.answers.tone.choice) ?? .playful
            : .playful
        let pacing = decoded.answers.pacing.confidence >= stylingConfidence
            ? ReactionPacing(rawValue: decoded.answers.pacing.choice) ?? .sustain
            : .sustain
        let flourish = decoded.answers.flourish.confidence >= stylingConfidence
            ? ReactionFlourish(rawValue: decoded.answers.flourish.choice) ?? .none
            : .none

        let candidateIDs = Set(candidates.map(\.id))
        let dialogueID: String?
        if decoded.answers.dialogue.confidence >= stylingConfidence,
           candidateIDs.contains(decoded.answers.dialogue.choice),
           DialogueCatalog.shared.line(id: decoded.answers.dialogue.choice)?.intent == intent {
            dialogueID = decoded.answers.dialogue.choice
        } else {
            dialogueID = nil
        }

        let maximumScore = 4.0
        let intensity = decoded.answers.intensity.confidence >= stylingConfidence
            ? decoded.answers.intensity.score / maximumScore
            : Double(snapshot.escalationLevel) / 5
        return ReactionPlan(
            intent: intent,
            intensity: intensity,
            confidence: decoded.answers.reaction.confidence,
            source: .jev,
            tone: tone,
            pacing: pacing,
            flourish: flourish,
            dialogueID: dialogueID
        )
    }

    public func makeRequest(for snapshot: ReactionSnapshot) throws -> URLRequest {
        try makeRequest(for: snapshot, candidates: DialogueCatalog.shared.shortlist(for: snapshot))
    }

    private func makeRequest(for snapshot: ReactionSnapshot, candidates: [DialogueLine]) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(JevRequest(state: snapshot, candidates: candidates))
        return request
    }
}

private struct JevRequest: Encodable {
    let state: ReactionSnapshot
    let model = JevReactionProvider.pinnedModel
    let questions: Questions

    init(state: ReactionSnapshot, candidates: [DialogueLine]) {
        self.state = state
        questions = Questions(candidates: candidates)
    }

    struct Questions: Encodable {
        let reaction: ChoiceQuestion
        let intensity: ScoreQuestion
        let tone: ChoiceQuestion
        let pacing: ChoiceQuestion
        let flourish: ChoiceQuestion
        let dialogue: ChoiceQuestion

        init(candidates: [DialogueLine]) {
            reaction = ChoiceQuestion(
                type: "choice",
                instructions: "Direct the fox's next reaction after the current burst has settled. Use motion energy, typing pace, coarse direction, session history, and escalation. Reserve promptDoubleEscape for persistent attempts.",
                criteria: [
                    "notice": "Wake and acknowledge gentle first movement.",
                    "followCursor": "Track continuing pointer movement.",
                    "stalkCursor": "Creep after sustained, deliberate pointer movement.",
                    "pounce": "Leap at a fast or frantic pointer movement.",
                    "bonk": "Respond to a click with the primary bonk gag.",
                    "swat": "Bat the pointer away after another click.",
                    "repeatBonk": "Respond to repeated or rapid clicking.",
                    "annoyed": "Show mild frustration at keyboard activity.",
                    "coverEars": "Cover both ears during sustained typing.",
                    "angry": "Show dramatic frustration at persistent high-rate activity.",
                    "blockShortcut": "Hold up a stop sign for a shortcut attempt.",
                    "cling": "Brace and cling during a small scroll.",
                    "tumble": "Get pushed or tumble in response to scrolling.",
                    "promptDoubleEscape": "Clearly explain that only deliberate double Escape starts owner authentication."
                ]
            )
            intensity = ScoreQuestion(
                type: "score",
                instructions: "Rate the energy for the next character beat.",
                criteria: [
                    "Barely react.",
                    "Notice without annoyance.",
                    "Playful standard reaction.",
                    "Clearly animated.",
                    "Maximum dramatic reaction."
                ]
            )
            tone = ChoiceQuestion(
                type: "choice",
                instructions: "Choose the fox's personality tone for this beat.",
                criteria: [
                    "playful": "Cheeky, warm, and game-like.",
                    "smug": "Confident that the guard has won.",
                    "grumpy": "Irritated but harmless.",
                    "encouraging": "Supportive about the user's failed attempt.",
                    "dramatic": "Comically theatrical and high stakes.",
                    "sleepy": "Drowsy, low-energy, and recently awakened."
                ]
            )
            pacing = ChoiceQuestion(
                type: "choice",
                instructions: "Choose how this beat should move the current mini-story.",
                criteria: [
                    "escalate": "Increase energy from the current state.",
                    "sustain": "Keep the current energy and rhythm.",
                    "coolDown": "Resolve the burst and settle the fox."
                ]
            )
            flourish = ChoiceQuestion(
                type: "choice",
                instructions: "Choose one safe visual flourish that supports the reaction.",
                criteria: [
                    "none": "Let the core state animation speak for itself.",
                    "hop": "Add a quick vertical hop.",
                    "shake": "Add an indignant shake.",
                    "spin": "Add a playful turn or tumble.",
                    "pose": "Hold a confident finishing pose.",
                    "sparkle": "Add a celebratory sparkle accent."
                ]
            )
            dialogue = ChoiceQuestion(
                type: "choice",
                instructions: "Choose the single dialogue line that best matches the same next reaction, tone, and energy. Prefer a line whose reaction label agrees with your reaction choice.",
                criteria: Dictionary(uniqueKeysWithValues: candidates.map { line in
                    (line.id, "\(line.intent.rawValue), \(line.tone.rawValue): \(line.text)")
                })
            )
        }
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
        let tone: ChoiceAnswer
        let pacing: ChoiceAnswer
        let flourish: ChoiceAnswer
        let dialogue: ChoiceAnswer
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
