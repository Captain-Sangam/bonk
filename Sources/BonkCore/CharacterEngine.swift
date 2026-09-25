import AppKit
import Combine
import Foundation

public enum CharacterState: String, Sendable {
    case idle
    case sleeping
    case notice
    case walk
    case stalk
    case run
    case pounce
    case point
    case bonk
    case repeatBonk
    case swat
    case annoyed
    case coverEars
    case angry
    case block
    case cling
    case dragged
    case tumble
    case celebrate
    case disappear
}

public struct NormalizedPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = min(max(x, 0), 1)
        self.y = min(max(y, 0), 1)
    }

    public static let resting = NormalizedPoint(x: 0.82, y: 0.16)
    public static let unlockHint = NormalizedPoint(x: 0.5, y: 0.2)
    public static let touchID = NormalizedPoint(x: 0.9, y: 0.9)
}

public struct CursorPresentation: Equatable, Sendable {
    public var position: NormalizedPoint?
    public var activeDisplayNumber: Int?

    public init(position: NormalizedPoint? = nil, activeDisplayNumber: Int? = nil) {
        self.position = position
        self.activeDisplayNumber = activeDisplayNumber
    }
}

public struct CharacterPresentation: Equatable, Sendable {
    public var state: CharacterState
    public var message: String?
    public var position: NormalizedPoint
    public var activeDisplayNumber: Int?
    public var intensity: Double
    public var lookX: Double
    public var lookY: Double
    public var facing: Double
    public var motionSpeed: Double
    public var inputDeltaX: Double
    public var inputDeltaY: Double
    public var variant: Int
    public var reactionStartedAt: TimeInterval
    public var tone: ReactionTone
    public var pacing: ReactionPacing
    public var flourish: ReactionFlourish
    public var typingScalePeak: Double
    public var typingDecayStartsAt: TimeInterval

    public init(
        state: CharacterState = .sleeping,
        message: String? = nil,
        position: NormalizedPoint = .resting,
        activeDisplayNumber: Int? = nil,
        intensity: Double = 0,
        lookX: Double = 0,
        lookY: Double = 0,
        facing: Double = 1,
        motionSpeed: Double = 0,
        inputDeltaX: Double = 0,
        inputDeltaY: Double = 0,
        variant: Int = 0,
        reactionStartedAt: TimeInterval = Date.timeIntervalSinceReferenceDate,
        tone: ReactionTone = .sleepy,
        pacing: ReactionPacing = .sustain,
        flourish: ReactionFlourish = .none,
        typingScalePeak: Double = 1.0,
        typingDecayStartsAt: TimeInterval = 0
    ) {
        self.state = state
        self.message = message
        self.position = position
        self.activeDisplayNumber = activeDisplayNumber
        self.intensity = intensity
        self.lookX = lookX
        self.lookY = lookY
        self.facing = facing
        self.motionSpeed = motionSpeed
        self.inputDeltaX = inputDeltaX
        self.inputDeltaY = inputDeltaY
        self.variant = variant
        self.reactionStartedAt = reactionStartedAt
        self.tone = tone
        self.pacing = pacing
        self.flourish = flourish
        self.typingScalePeak = min(max(typingScalePeak, TypingScaleEnvelope.normalScale), TypingScaleEnvelope.maximumScale)
        self.typingDecayStartsAt = typingDecayStartsAt
    }

    public func typingScale(at timestamp: TimeInterval) -> Double {
        TypingScaleEnvelope(
            peakScale: typingScalePeak,
            decayStartsAt: typingDecayStartsAt
        ).scale(at: timestamp)
    }
}

@MainActor
public final class CharacterEngine: ObservableObject, CharacterPresenting {
    @Published public private(set) var presentation = CharacterPresentation()
    @Published public private(set) var cursorPresentation = CursorPresentation()

    private var soundsEnabled: () -> Bool
    private var reactionSequence = 0
    private var typingScaleTracker = TypingScaleTracker()
    private var recentDialogueIDs: [String] = []

    public init(soundsEnabled: @escaping () -> Bool) {
        self.soundsEnabled = soundsEnabled
    }

    public func reset() {
        reactionSequence = 0
        typingScaleTracker.reset()
        recentDialogueIDs.removeAll(keepingCapacity: true)
        presentation = CharacterPresentation()
        cursorPresentation = CursorPresentation()
    }

    public func context(for point: CGPoint?) -> (displayIndex: Int?, region: CoarseCursorRegion) {
        guard let point,
              let match = NSScreen.screens.enumerated().first(where: { $0.element.frame.contains(point) })
        else {
            return (nil, .unknown)
        }

        return (match.offset, Self.region(for: point, in: match.element.frame))
    }

    public func observe(_ signal: InteractionSignal) {
        var next = presentation
        if (signal.kind == .keyboardActivity || signal.kind == .shortcutAttempt), !signal.isAutoRepeat {
            let envelope = typingScaleTracker.record(signal)
            next.typingScalePeak = envelope.peakScale
            next.typingDecayStartsAt = envelope.decayStartsAt
        }

        guard let point = signal.globalLocation,
              let (screen, normalized) = Self.screenPosition(for: point)
        else {
            presentation = next
            return
        }

        let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? Int
        cursorPresentation = CursorPresentation(position: normalized, activeDisplayNumber: displayNumber)
        next.activeDisplayNumber = displayNumber
        next.inputDeltaX = min(max(signal.deltaX / 40, -1), 1)
        next.inputDeltaY = min(max(signal.deltaY / 40, -1), 1)
        next.motionSpeed = min(max(signal.magnitude / 1_200, 0), 1)

        let horizontalDistance = normalized.x - next.position.x
        let verticalDistance = normalized.y - next.position.y
        next.lookX = min(max(horizontalDistance * 4, -1), 1)
        next.lookY = min(max(verticalDistance * 4, -1), 1)
        if abs(signal.deltaX) > 0.25 {
            next.facing = signal.deltaX < 0 ? -1 : 1
        } else if abs(horizontalDistance) > 0.02 {
            next.facing = horizontalDistance < 0 ? -1 : 1
        }

        if signal.kind == .mouseMovement {
            let trail = NormalizedPoint(
                x: normalized.x - (next.facing * 0.06),
                y: normalized.y - 0.07
            )
            let followStrength = 0.16 + (next.motionSpeed * 0.28)
            next.position = Self.interpolate(from: next.position, to: trail, amount: followStrength)
        }

        presentation = next
    }

    public func apply(_ plan: ReactionPlan, near point: CGPoint?) {
        var next = presentation
        reactionSequence += 1
        next.state = state(for: plan.intent)
        next.variant = reactionSequence
        next.message = message(for: plan)
        next.tone = plan.tone
        next.pacing = plan.pacing
        next.flourish = plan.flourish
        switch plan.pacing {
        case .escalate:
            next.intensity = max(plan.intensity, min(next.intensity + 0.2, 1))
        case .sustain:
            next.intensity = plan.intensity
        case .coolDown:
            next.intensity = min(plan.intensity, 0.45)
        }
        next.reactionStartedAt = Date.timeIntervalSinceReferenceDate

        if let point, let (screen, normalized) = Self.screenPosition(for: point) {
            let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? Int
            next.activeDisplayNumber = displayNumber
            cursorPresentation = CursorPresentation(position: normalized, activeDisplayNumber: displayNumber)
            next.lookX = min(max((normalized.x - next.position.x) * 4, -1), 1)
            next.lookY = min(max((normalized.y - next.position.y) * 4, -1), 1)

            switch plan.intent {
            case .followCursor, .stalkCursor:
                let trailingPoint = NormalizedPoint(
                    x: normalized.x - (next.facing * 0.06),
                    y: normalized.y - 0.07
                )
                next.position = Self.interpolate(from: next.position, to: trailingPoint, amount: 0.3)
            case .pounce:
                next.position = NormalizedPoint(
                    x: normalized.x - (next.facing * 0.025),
                    y: normalized.y - 0.045
                )
            case .bonk, .swat, .repeatBonk:
                next.position = NormalizedPoint(
                    x: normalized.x - (next.facing * 0.055),
                    y: normalized.y - 0.06
                )
            case .cling, .tumble:
                next.position = NormalizedPoint(
                    x: next.position.x + (next.inputDeltaX * 0.055),
                    y: next.position.y + (next.inputDeltaY * 0.035)
                )
            default:
                break
            }
        }

        if plan.intent == .promptDoubleEscape {
            next.position = .unlockHint
            next.facing = 1
        }

        presentation = next
        playSound(for: plan.intent)
    }

    public func pointToAuthentication() {
        presentation.state = .point
        presentation.message = "Double Esc captured. Use Touch ID."
        presentation.position = .touchID
        presentation.facing = 1
        presentation.intensity = 0.5
        presentation.tone = .encouraging
        presentation.pacing = .coolDown
        presentation.flourish = .pose
        presentation.variant += 1
        presentation.reactionStartedAt = Date.timeIntervalSinceReferenceDate
    }

    public func celebrate() {
        presentation.state = .celebrate
        presentation.message = "BONK OFF!"
        presentation.intensity = 1
        presentation.tone = .playful
        presentation.pacing = .coolDown
        presentation.flourish = .sparkle
        presentation.variant += 1
        presentation.reactionStartedAt = Date.timeIntervalSinceReferenceDate
        if soundsEnabled() {
            NSSound(named: NSSound.Name("Glass"))?.play()
        }
    }

    private func state(for intent: ReactionIntent) -> CharacterState {
        switch intent {
        case .notice: return .notice
        case .followCursor: return .walk
        case .stalkCursor: return .stalk
        case .pounce: return .pounce
        case .bonk: return .bonk
        case .repeatBonk: return .repeatBonk
        case .swat: return .swat
        case .annoyed: return .annoyed
        case .coverEars: return .coverEars
        case .angry: return .angry
        case .blockShortcut: return .block
        case .cling: return .cling
        case .tumble: return .tumble
        case .promptDoubleEscape: return .point
        }
    }

    private func message(for plan: ReactionPlan) -> String? {
        let catalog = DialogueCatalog.shared
        let selected: DialogueLine?

        if let directed = catalog.line(id: plan.dialogueID),
           directed.intent == plan.intent,
           !recentDialogueIDs.contains(directed.id) {
            selected = directed
        } else {
            selected = catalog.select(
                intent: plan.intent,
                tone: plan.tone,
                excluding: Set(recentDialogueIDs),
                seed: reactionSequence
            )
        }

        guard let selected else { return nil }
        recentDialogueIDs.append(selected.id)
        if recentDialogueIDs.count > 10 {
            recentDialogueIDs.removeFirst(recentDialogueIDs.count - 10)
        }
        return selected.text
    }

    private func playSound(for intent: ReactionIntent) {
        guard soundsEnabled(), intent == .bonk || intent == .repeatBonk else { return }
        NSSound(named: NSSound.Name("Tink"))?.play()
    }

    private static func region(for point: CGPoint, in frame: CGRect) -> CoarseCursorRegion {
        let x = (point.x - frame.minX) / frame.width
        let y = (point.y - frame.minY) / frame.height
        let column = x < 1.0 / 3 ? 0 : (x > 2.0 / 3 ? 2 : 1)
        let row = y < 1.0 / 3 ? 0 : (y > 2.0 / 3 ? 2 : 1)

        switch (column, row) {
        case (0, 2): return .topLeft
        case (1, 2): return .top
        case (2, 2): return .topRight
        case (0, 1): return .left
        case (1, 1): return .center
        case (2, 1): return .right
        case (0, 0): return .bottomLeft
        case (1, 0): return .bottom
        case (2, 0): return .bottomRight
        default: return .unknown
        }
    }

    private static func screenPosition(for point: CGPoint) -> (NSScreen, NormalizedPoint)? {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { return nil }
        return (
            screen,
            NormalizedPoint(
                x: (point.x - screen.frame.minX) / screen.frame.width,
                y: (point.y - screen.frame.minY) / screen.frame.height
            )
        )
    }

    private static func interpolate(
        from start: NormalizedPoint,
        to end: NormalizedPoint,
        amount: Double
    ) -> NormalizedPoint {
        NormalizedPoint(
            x: start.x + ((end.x - start.x) * amount),
            y: start.y + ((end.y - start.y) * amount)
        )
    }
}
