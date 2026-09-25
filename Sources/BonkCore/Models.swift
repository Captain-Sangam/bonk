import CoreGraphics
import Foundation

public enum GuardStatus: String, Equatable, Sendable {
    case idle
    case armed
    case reacting
    case authenticating

    public var isGuarding: Bool { self != .idle }
}

public enum InteractionKind: String, Codable, CaseIterable, Hashable, Sendable {
    case mouseMovement
    case click
    case rapidClick
    case keyboardActivity
    case scroll
    case shortcutAttempt
}

public struct InteractionSignal: Sendable {
    public let kind: InteractionKind
    public let timestamp: Date
    public let globalLocation: CGPoint?
    public let magnitude: Double
    public let deltaX: Double
    public let deltaY: Double
    public let isAutoRepeat: Bool

    public init(
        kind: InteractionKind,
        timestamp: Date = Date(),
        globalLocation: CGPoint? = nil,
        magnitude: Double = 1,
        deltaX: Double = 0,
        deltaY: Double = 0,
        isAutoRepeat: Bool = false
    ) {
        self.kind = kind
        self.timestamp = timestamp
        self.globalLocation = globalLocation
        self.magnitude = magnitude
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.isAutoRepeat = isAutoRepeat
    }
}

public enum MotionEnergy: String, Codable, Sendable {
    case still
    case gentle
    case quick
    case frantic
}

public enum CoarseDirection: String, Codable, Sendable {
    case stationary
    case left
    case right
    case up
    case down
}

public enum InteractionRate: String, Codable, Sendable {
    case low
    case medium
    case high
}

public enum TypingPace: String, Codable, Sendable {
    case none
    case slow
    case steady
    case fast
    case frantic
}

public enum ReactionTone: String, Codable, CaseIterable, Sendable {
    case playful
    case smug
    case grumpy
    case encouraging
    case dramatic
    case sleepy
}

public enum ReactionPacing: String, Codable, CaseIterable, Sendable {
    case escalate
    case sustain
    case coolDown
}

public enum ReactionFlourish: String, Codable, CaseIterable, Sendable {
    case none
    case hop
    case shake
    case spin
    case pose
    case sparkle
}

public enum SessionDurationBucket: String, Codable, Sendable {
    case justStarted
    case short
    case established
    case long
}

public enum CoarseCursorRegion: String, Codable, Sendable {
    case topLeft
    case top
    case topRight
    case left
    case center
    case right
    case bottomLeft
    case bottom
    case bottomRight
    case unknown
}

public enum ReactionIntent: String, Codable, CaseIterable, Hashable, Sendable {
    case notice
    case followCursor
    case stalkCursor
    case pounce
    case bonk
    case swat
    case repeatBonk
    case annoyed
    case coverEars
    case angry
    case blockShortcut
    case cling
    case tumble
    case promptDoubleEscape
}

public struct ReactionSnapshot: Codable, Equatable, Sendable {
    public let interaction: InteractionKind
    public let recentEventCounts: [String: Int]
    public let interactionRate: InteractionRate
    public let sessionDuration: SessionDurationBucket
    public let escalationLevel: Int
    public let currentCharacterState: String
    public let displayIndex: Int?
    public let cursorRegion: CoarseCursorRegion
    public let motionEnergy: MotionEnergy
    public let coarseDirection: CoarseDirection
    public let typingPace: TypingPace
    public let recentCharacterBeats: [String]

    public init(
        interaction: InteractionKind,
        recentEventCounts: [String: Int],
        interactionRate: InteractionRate,
        sessionDuration: SessionDurationBucket,
        escalationLevel: Int,
        currentCharacterState: String,
        displayIndex: Int?,
        cursorRegion: CoarseCursorRegion,
        motionEnergy: MotionEnergy = .still,
        coarseDirection: CoarseDirection = .stationary,
        typingPace: TypingPace = .none,
        recentCharacterBeats: [String] = []
    ) {
        self.interaction = interaction
        self.recentEventCounts = recentEventCounts
        self.interactionRate = interactionRate
        self.sessionDuration = sessionDuration
        self.escalationLevel = min(max(escalationLevel, 0), 5)
        self.currentCharacterState = currentCharacterState
        self.displayIndex = displayIndex
        self.cursorRegion = cursorRegion
        self.motionEnergy = motionEnergy
        self.coarseDirection = coarseDirection
        self.typingPace = typingPace
        self.recentCharacterBeats = Array(recentCharacterBeats.suffix(3))
    }
}

public struct ReactionPlan: Equatable, Sendable {
    public let intent: ReactionIntent
    public let intensity: Double
    public let confidence: Double
    public let source: Source
    public let tone: ReactionTone
    public let pacing: ReactionPacing
    public let flourish: ReactionFlourish
    public let dialogueID: String?

    public enum Source: String, Equatable, Sendable {
        case local
        case jev
    }

    public init(
        intent: ReactionIntent,
        intensity: Double,
        confidence: Double,
        source: Source,
        tone: ReactionTone = .playful,
        pacing: ReactionPacing = .sustain,
        flourish: ReactionFlourish = .none,
        dialogueID: String? = nil
    ) {
        self.intent = intent
        self.intensity = min(max(intensity, 0), 1)
        self.confidence = min(max(confidence, 0), 1)
        self.source = source
        self.tone = tone
        self.pacing = pacing
        self.flourish = flourish
        self.dialogueID = dialogueID
    }
}

public enum BonkError: LocalizedError, Equatable {
    case accessibilityPermissionMissing
    case eventTapCreationFailed
    case eventTapDisabled
    case overlayUnavailable(String)
    case authenticationUnavailable(String)
    case authenticationFailed(String)
    case jevUnavailable
    case invalidJevResponse
    case launchAtLoginUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            return "Bonk needs Accessibility permission to guard keyboard and pointing-device input."
        case .eventTapCreationFailed:
            return "Bonk could not start its input guard."
        case .eventTapDisabled:
            return "macOS disabled Bonk’s input guard, so Guard Mode was stopped safely."
        case let .overlayUnavailable(reason):
            return "Bonk could not protect every display: \(reason)"
        case let .authenticationUnavailable(reason):
            return "Owner authentication is unavailable: \(reason)"
        case let .authenticationFailed(reason):
            return "Owner authentication failed: \(reason)"
        case .jevUnavailable:
            return "Jev is unavailable. Bonk is using local reactions."
        case .invalidJevResponse:
            return "Jev returned an unsupported reaction. Bonk is using a local reaction."
        case let .launchAtLoginUnavailable(reason):
            return "Launch at login could not be changed: \(reason)"
        }
    }
}
