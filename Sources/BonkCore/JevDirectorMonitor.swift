import Combine
import Foundation

public enum JevDirectorPhase: String, Sendable {
    case localOnly
    case waiting
    case directing
    case applied
    case unavailable

    public var label: String {
        switch self {
        case .localOnly: return "Local reactions"
        case .waiting: return "Waiting for input to settle"
        case .directing: return "Jev is directing"
        case .applied: return "Jev direction applied"
        case .unavailable: return "Local fallback active"
        }
    }
}

@MainActor
public final class JevDirectorMonitor: ObservableObject {
    @Published public private(set) var phase: JevDirectorPhase = .localOnly
    @Published public private(set) var lastDecision: String?
    @Published public private(set) var requestCount = 0

    public init() {}

    func reset(enabled: Bool, hasAPIKey: Bool) {
        requestCount = 0
        lastDecision = nil
        phase = enabled && hasAPIKey ? .waiting : .localOnly
    }

    func markWaiting() {
        phase = .waiting
    }

    func markDirecting() {
        requestCount += 1
        phase = .directing
    }

    func markApplied(_ plan: ReactionPlan) {
        phase = .applied
        lastDecision = [
            plan.intent.rawValue,
            plan.tone.rawValue,
            plan.pacing.rawValue,
            plan.flourish.rawValue
        ].joined(separator: " · ")
    }

    func markUnavailable() {
        phase = .unavailable
    }

    func markLocalOnly() {
        phase = .localOnly
    }
}
