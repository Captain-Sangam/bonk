import Foundation

@MainActor
public final class ReactionController: ReactionControlling {
    public typealias Configuration = (enabled: Bool, apiKey: String?)
    public typealias ProviderFactory = @Sendable (String) -> any ReactionProvider

    private let characterEngine: CharacterEngine
    private let configuration: () -> Configuration
    private let quietPeriodNanoseconds: UInt64
    private let providerFactory: ProviderFactory
    private let localProvider = LocalReactionProvider()
    public let director: JevDirectorMonitor
    private var aggregator = InteractionAggregator()
    private var sessionID = UUID()
    private var eventSequence = 0
    private var pendingTask: Task<Void, Never>?
    private var pendingTaskID: UUID?
    private var jevRequestInFlight = false
    private var quietDeadline: Date?
    private var latestSnapshot: ReactionSnapshot?
    private var latestLocation: CGPoint?
    private var recentCharacterBeats: [String] = []
    private var lastPresentedAt = Date.distantPast
    private var lastPresentedIntent: ReactionIntent?

    public init(
        characterEngine: CharacterEngine,
        director: JevDirectorMonitor,
        quietPeriodNanoseconds: UInt64 = 2_000_000_000,
        providerFactory: @escaping ProviderFactory = { JevReactionProvider(apiKey: $0) },
        configuration: @escaping () -> Configuration
    ) {
        self.characterEngine = characterEngine
        self.director = director
        self.quietPeriodNanoseconds = quietPeriodNanoseconds
        self.providerFactory = providerFactory
        self.configuration = configuration
    }

    public convenience init(
        characterEngine: CharacterEngine,
        configuration: @escaping () -> Configuration
    ) {
        self.init(
            characterEngine: characterEngine,
            director: JevDirectorMonitor(),
            configuration: configuration
        )
    }

    public func beginSession() {
        pendingTask?.cancel()
        pendingTask = nil
        pendingTaskID = nil
        jevRequestInFlight = false
        quietDeadline = nil
        latestSnapshot = nil
        latestLocation = nil
        recentCharacterBeats.removeAll(keepingCapacity: true)
        sessionID = UUID()
        eventSequence = 0
        lastPresentedAt = .distantPast
        lastPresentedIntent = nil
        aggregator.reset()
        characterEngine.reset()
        let currentConfiguration = configuration()
        director.reset(
            enabled: currentConfiguration.enabled,
            hasAPIKey: currentConfiguration.apiKey != nil
        )
    }

    public func handle(_ signal: InteractionSignal) {
        eventSequence += 1
        characterEngine.observe(signal)
        let context = characterEngine.context(for: signal.globalLocation)
        let snapshot = aggregator.record(
            signal,
            characterState: characterEngine.presentation.state.rawValue,
            displayIndex: context.displayIndex,
            cursorRegion: context.region,
            recentCharacterBeats: recentCharacterBeats
        )

        let localPlan = localProvider.immediateReaction(for: snapshot)
        let isNewIntent = localPlan.intent != lastPresentedIntent
        let presentationInterval = signal.timestamp.timeIntervalSince(lastPresentedAt)
        let shouldPresent: Bool
        switch signal.kind {
        case .click, .rapidClick, .shortcutAttempt:
            shouldPresent = true
        case .mouseMovement, .keyboardActivity, .scroll:
            shouldPresent = isNewIntent || presentationInterval >= 0.65
        }

        if shouldPresent {
            lastPresentedAt = signal.timestamp
            lastPresentedIntent = localPlan.intent
            characterEngine.apply(localPlan, near: signal.globalLocation)
            remember(localPlan)
        }

        let currentConfiguration = configuration()
        guard currentConfiguration.enabled, let apiKey = currentConfiguration.apiKey else {
            pendingTask?.cancel()
            pendingTask = nil
            pendingTaskID = nil
            jevRequestInFlight = false
            quietDeadline = nil
            director.markLocalOnly()
            return
        }

        latestSnapshot = snapshotForJev(from: snapshot)
        latestLocation = signal.globalLocation
        quietDeadline = Date().addingTimeInterval(Double(quietPeriodNanoseconds) / 1_000_000_000)
        director.markWaiting()

        if jevRequestInFlight {
            pendingTask?.cancel()
            pendingTask = nil
            pendingTaskID = nil
            jevRequestInFlight = false
        }
        scheduleJevEvaluation(for: sessionID, apiKey: apiKey)
    }

    public func pointToAuthentication() {
        pendingTask?.cancel()
        pendingTask = nil
        pendingTaskID = nil
        jevRequestInFlight = false
        quietDeadline = nil
        director.markLocalOnly()
        characterEngine.pointToAuthentication()
    }

    public func endSession() {
        pendingTask?.cancel()
        pendingTask = nil
        pendingTaskID = nil
        jevRequestInFlight = false
        quietDeadline = nil
        latestSnapshot = nil
        latestLocation = nil
        recentCharacterBeats.removeAll(keepingCapacity: true)
        sessionID = UUID()
        director.markLocalOnly()
    }

    private func scheduleJevEvaluation(for session: UUID, apiKey: String) {
        guard pendingTask == nil else { return }

        let taskID = UUID()
        pendingTaskID = taskID
        let providerFactory = self.providerFactory
        pendingTask = Task { [weak self] in
            guard let self else { return }

            do {
                while true {
                    try Task.checkCancellation()
                    guard self.sessionID == session,
                          let deadline = self.quietDeadline
                    else {
                        self.finishTask(taskID)
                        return
                    }

                    let remaining = deadline.timeIntervalSinceNow
                    if remaining > 0 {
                        try await Task.sleep(
                            nanoseconds: UInt64(min(remaining, 60) * 1_000_000_000)
                        )
                        continue
                    }

                    guard let snapshot = self.latestSnapshot else {
                        self.finishTask(taskID)
                        return
                    }
                    let requestSequence = self.eventSequence
                    let location = self.latestLocation

                    self.jevRequestInFlight = true
                    self.director.markDirecting()
                    let provider = providerFactory(apiKey)
                    let plan = try await provider.reaction(for: snapshot)
                    try Task.checkCancellation()

                    guard self.sessionID == session,
                          self.eventSequence == requestSequence
                    else {
                        self.finishTask(taskID)
                        return
                    }

                    self.characterEngine.apply(plan, near: location)
                    self.remember(plan)
                    self.director.markApplied(plan)
                    self.finishTask(taskID)
                    return
                }
            } catch {
                // The local reaction is already visible. Network and model failures
                // are deliberately silent and never affect Guard Mode.
                guard !Task.isCancelled,
                      self.sessionID == session,
                      self.pendingTaskID == taskID
                else {
                    return
                }
                self.director.markUnavailable()
                self.finishTask(taskID)
            }
        }
    }

    private func finishTask(_ taskID: UUID) {
        guard pendingTaskID == taskID else { return }
        pendingTask = nil
        pendingTaskID = nil
        jevRequestInFlight = false
    }

    private func remember(_ plan: ReactionPlan) {
        recentCharacterBeats.append(
            [plan.intent.rawValue, plan.tone.rawValue, plan.pacing.rawValue]
                .joined(separator: "|")
        )
        if recentCharacterBeats.count > 3 {
            recentCharacterBeats.removeFirst(recentCharacterBeats.count - 3)
        }
    }

    private func snapshotForJev(from snapshot: ReactionSnapshot) -> ReactionSnapshot {
        ReactionSnapshot(
            interaction: snapshot.interaction,
            recentEventCounts: snapshot.recentEventCounts,
            interactionRate: snapshot.interactionRate,
            sessionDuration: snapshot.sessionDuration,
            escalationLevel: snapshot.escalationLevel,
            currentCharacterState: characterEngine.presentation.state.rawValue,
            displayIndex: snapshot.displayIndex,
            cursorRegion: snapshot.cursorRegion,
            motionEnergy: snapshot.motionEnergy,
            coarseDirection: snapshot.coarseDirection,
            typingPace: snapshot.typingPace,
            recentCharacterBeats: recentCharacterBeats
        )
    }
}
