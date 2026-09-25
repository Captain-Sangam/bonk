import Foundation

struct TypingScaleEnvelope: Equatable, Sendable {
    static let normalScale = 1.0
    static let maximumScale = 1.65
    static let decayDelay: TimeInterval = 0.35
    static let decayDuration: TimeInterval = 4.0

    var peakScale: Double = normalScale
    var decayStartsAt: TimeInterval = 0

    func scale(at timestamp: TimeInterval) -> Double {
        guard peakScale > Self.normalScale else { return Self.normalScale }
        guard timestamp > decayStartsAt else { return peakScale }

        let progress = min(max((timestamp - decayStartsAt) / Self.decayDuration, 0), 1)
        let smoothProgress = progress * progress * (3 - (2 * progress))
        return Self.normalScale + ((peakScale - Self.normalScale) * (1 - smoothProgress))
    }
}

struct TypingScaleTracker: Sendable {
    static let rollingWindow: TimeInterval = 1.5
    static let maximumKeysPerSecond = 8.0

    private var keystrokes: [TimeInterval] = []
    private(set) var envelope = TypingScaleEnvelope()

    mutating func reset() {
        keystrokes.removeAll(keepingCapacity: true)
        envelope = TypingScaleEnvelope()
    }

    @discardableResult
    mutating func record(_ signal: InteractionSignal) -> TypingScaleEnvelope {
        guard signal.kind == .keyboardActivity || signal.kind == .shortcutAttempt,
              !signal.isAutoRepeat
        else {
            return envelope
        }

        let timestamp = signal.timestamp.timeIntervalSinceReferenceDate
        let cutoff = timestamp - Self.rollingWindow
        keystrokes.removeAll { $0 < cutoff }
        keystrokes.append(timestamp)

        let keysPerSecond = Double(keystrokes.count) / Self.rollingWindow
        let charge = min(max(keysPerSecond / Self.maximumKeysPerSecond, 0), 1)
        let measuredScale = TypingScaleEnvelope.normalScale
            + (charge * (TypingScaleEnvelope.maximumScale - TypingScaleEnvelope.normalScale))
        let currentScale = envelope.scale(at: timestamp)

        envelope = TypingScaleEnvelope(
            peakScale: min(max(max(currentScale, measuredScale), TypingScaleEnvelope.normalScale), TypingScaleEnvelope.maximumScale),
            decayStartsAt: timestamp + TypingScaleEnvelope.decayDelay
        )
        return envelope
    }
}
