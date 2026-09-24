import AppKit
import Combine
import Foundation

public enum CharacterState: String, Sendable {
    case idle
    case sleeping
    case notice
    case walk
    case run
    case point
    case bonk
    case annoyed
    case angry
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

    public init(
        state: CharacterState = .sleeping,
        message: String? = nil,
        position: NormalizedPoint = .resting,
        activeDisplayNumber: Int? = nil,
        intensity: Double = 0
    ) {
        self.state = state
        self.message = message
        self.position = position
        self.activeDisplayNumber = activeDisplayNumber
        self.intensity = intensity
    }
}

@MainActor
public final class CharacterEngine: ObservableObject, CharacterPresenting {
    @Published public private(set) var presentation = CharacterPresentation()

    private var soundsEnabled: () -> Bool

    public init(soundsEnabled: @escaping () -> Bool) {
        self.soundsEnabled = soundsEnabled
    }

    public func reset() {
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

    public func apply(_ plan: ReactionPlan, near point: CGPoint?) {
        var next = presentation
        next.state = state(for: plan.intent)
        next.message = message(for: plan.intent)
        next.intensity = plan.intensity

        if let point,
           let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            next.activeDisplayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? Int
            next.position = NormalizedPoint(
                x: (point.x - screen.frame.minX) / screen.frame.width,
                y: (point.y - screen.frame.minY) / screen.frame.height
            )
        }

        if plan.intent == .pointToTouchID {
            next.position = .touchID
        }

        presentation = next
        playSound(for: plan.intent)
    }

    public func pointToAuthentication() {
        presentation.state = .point
        presentation.message = "Owner? Use the finger."
        presentation.position = .touchID
        presentation.intensity = 0.5
    }

    public func celebrate() {
        presentation.state = .celebrate
        presentation.message = "✨ BONK OFF ✨"
        presentation.intensity = 1
        if soundsEnabled() {
            NSSound(named: NSSound.Name("Glass"))?.play()
        }
    }

    private func state(for intent: ReactionIntent) -> CharacterState {
        switch intent {
        case .notice: return .notice
        case .followCursor: return .walk
        case .bonk, .repeatBonk: return .bonk
        case .annoyed: return .annoyed
        case .angry, .blockShortcut: return .angry
        case .tumble: return .tumble
        case .pointToTouchID: return .point
        }
    }

    private func message(for intent: ReactionIntent) -> String? {
        switch intent {
        case .notice: return "hey."
        case .followCursor: return "i see that."
        case .bonk: return "BONK!"
        case .repeatBonk: return "bonk bonk."
        case .annoyed: return "nope."
        case .angry: return "seriously?"
        case .blockShortcut: return "🚫"
        case .tumble: return "whoa."
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
}
