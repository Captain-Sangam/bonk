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
    public static let touchID = NormalizedPoint(x: 0.9, y: 0.9)
}

public struct CharacterPresentation: Equatable, Sendable {
    public var state: CharacterState
    public var message: String?
    public var position: NormalizedPoint
    public var activeDisplayNumber: Int?
    public var intensity: Double
    public var cursorPosition: NormalizedPoint?
    public var lookX: Double
    public var lookY: Double
    public var facing: Double
    public var motionSpeed: Double
    public var inputDeltaX: Double
    public var inputDeltaY: Double
    public var variant: Int
    public var reactionStartedAt: TimeInterval

    public init(
        state: CharacterState = .sleeping,
        message: String? = nil,
        position: NormalizedPoint = .resting,
        activeDisplayNumber: Int? = nil,
        intensity: Double = 0,
        cursorPosition: NormalizedPoint? = nil,
        lookX: Double = 0,
        lookY: Double = 0,
        facing: Double = 1,
        motionSpeed: Double = 0,
        inputDeltaX: Double = 0,
        inputDeltaY: Double = 0,
        variant: Int = 0,
        reactionStartedAt: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) {
        self.state = state
        self.message = message
        self.position = position
        self.activeDisplayNumber = activeDisplayNumber
        self.intensity = intensity
        self.cursorPosition = cursorPosition
        self.lookX = lookX
        self.lookY = lookY
        self.facing = facing
        self.motionSpeed = motionSpeed
        self.inputDeltaX = inputDeltaX
        self.inputDeltaY = inputDeltaY
        self.variant = variant
        self.reactionStartedAt = reactionStartedAt
    }
}

@MainActor
public final class CharacterEngine: ObservableObject, CharacterPresenting {
    @Published public private(set) var presentation = CharacterPresentation()

    private var soundsEnabled: () -> Bool
    private var reactionSequence = 0

    public init(soundsEnabled: @escaping () -> Bool) {
        self.soundsEnabled = soundsEnabled
    }

    public func reset() {
        reactionSequence = 0
        presentation = CharacterPresentation()
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
        guard let point = signal.globalLocation,
              let (screen, normalized) = Self.screenPosition(for: point)
        else { return }

        var next = presentation
        next.activeDisplayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? Int
        next.cursorPosition = normalized
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
        next.message = message(for: plan.intent, variant: reactionSequence)
        next.intensity = plan.intensity
        next.reactionStartedAt = Date.timeIntervalSinceReferenceDate

        if let point, let (screen, normalized) = Self.screenPosition(for: point) {
            next.activeDisplayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? Int
            next.cursorPosition = normalized
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

        if plan.intent == .pointToTouchID {
            next.position = .touchID
            next.facing = 1
        }

        presentation = next
        playSound(for: plan.intent)
    }

    public func pointToAuthentication() {
        presentation.state = .point
        presentation.message = "Owner? Use the finger."
        presentation.position = .touchID
        presentation.facing = 1
        presentation.intensity = 0.5
        presentation.variant += 1
        presentation.reactionStartedAt = Date.timeIntervalSinceReferenceDate
    }

    public func celebrate() {
        presentation.state = .celebrate
        presentation.message = "BONK OFF!"
        presentation.intensity = 1
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
        case .bonk, .repeatBonk: return .bonk
        case .swat: return .swat
        case .annoyed: return .annoyed
        case .coverEars: return .coverEars
        case .angry: return .angry
        case .blockShortcut: return .block
        case .cling: return .cling
        case .tumble: return .tumble
        case .pointToTouchID: return .point
        }
    }

    private func message(for intent: ReactionIntent, variant: Int) -> String? {
        func pick(_ messages: [String]) -> String { messages[variant % messages.count] }

        switch intent {
        case .notice: return pick(["...oh?", "caught you.", "tiny paws. big job."])
        case .followCursor: return pick(["I see that cursor.", "nice try.", "where are we going?"])
        case .stalkCursor: return pick(["stealth mode.", "I can do this all day.", "still watching."])
        case .pounce: return pick(["GOTCHA.", "pounce protocol!", "too fast? never."])
        case .bonk: return pick(["BONK!", "boop denied.", "not today."])
        case .swat: return pick(["swat.", "hands off.", "back you go."])
        case .repeatBonk: return pick(["BONK BONK.", "again? really?", "rapid bonk mode."])
        case .annoyed: return pick(["nope.", "I heard that.", "keyboard privileges revoked."])
        case .coverEars: return pick(["too loud.", "my ears!", "typing detected. regrettably."])
        case .angry: return pick(["seriously?", "dude.", "you chose chaos."])
        case .blockShortcut: return pick(["shortcut denied.", "absolutely not.", "nice try, power user."])
        case .cling: return pick(["hold still!", "who moved the floor?", "claws deployed."])
        case .tumble: return pick(["wheee—NO.", "gravity filed a complaint.", "I meant to do that."])
        case .pointToTouchID: return "Use the finger."
        }
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
