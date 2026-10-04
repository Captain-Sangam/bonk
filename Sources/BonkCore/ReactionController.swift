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
    private var aggregator: InteractionAggregator
    private let displayInterval: TimeInterval
    private let restInterval: TimeInterval
    private var isSessionActive = false
    private var isResting = false
    private var lastStateChangeAt = Date.distantPast
    private var lastMessageChangeAt = Date.distantPast
    private var pendingMessage: PendingMessage?
    private var messageTask: Task<Void, Never>?
    private var messageTaskID: UUID?
    private var restTask: Task<Void, Never>?
    private var restTaskID: UUID?

    private enum PendingMessage {
        case reaction(ReactionPlan, localFallback: ReactionPlan? = nil)
        case authentication
    }

    private var messageDeadline: Date { lastMessageChangeAt.addingTimeInterval(displayInterval) }
    private var changeDeadline: Date { lastStateChangeAt.addingTimeInterval(displayInterval) }
    private var sessionID = UUID()
    private var eventSequence = 0
    private var pendingTask: Task<Void, Never>?
    private var pendingTaskID: UUID?
    private var jevRequestInFlight = false
    private var quietDeadline: Date?
    private var latestSnapshot: ReactionSnapshot?
    private var latestLocation: CGPoint?
    private var recentCharacterBeats: [String] = []

    public init(
        characterEngine: CharacterEngine,
        director: JevDirectorMonitor,
        quietPeriodNanoseconds: UInt64 = 2_000_000_000,
        displayInterval: TimeInterval = 4,
        restInterval: TimeInterval = 20,
        gestureGap: TimeInterval = 0.75,
        providerFactory: @escaping ProviderFactory = { JevReactionProvider(apiKey: $0) },
        configuration: @escaping () -> Configuration
    ) {
        self.characterEngine = characterEngine
        self.director = director
        self.quietPeriodNanoseconds = quietPeriodNanoseconds
        self.displayInterval = max(displayInterval, 0)
        self.restInterval = max(restInterval, 0)
        self.aggregator = InteractionAggregator(gestureGap: gestureGap)
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
        cancelJevEvaluation()
        cancelPendingMessage()
        cancelRest()
        isSessionActive = true
        isResting = false
        latestSnapshot = nil
        latestLocation = nil
        recentCharacterBeats.removeAll(keepingCapacity: true)
        sessionID = UUID()
        eventSequence = 0
        lastStateChangeAt = .distantPast
        lastMessageChangeAt = .distantPast
        aggregator.reset()
        characterEngine.reset()
        let currentConfiguration = configuration()
        director.reset(
            enabled: currentConfiguration.enabled,
            hasAPIKey: currentConfiguration.apiKey != nil
        )
        scheduleRest(at: Date().addingTimeInterval(restInterval))
    }

    public func handle(_ signal: InteractionSignal) {
        guard isSessionActive else { return }
        eventSequence += 1
        let waking = isResting
        isResting = false
        characterEngine.observe(
            signal,
            holdingPosition: characterEngine.presentation.message != nil && signal.timestamp < messageDeadline
        )
        let context = characterEngine.context(for: signal.globalLocation)
        let snapshot = aggregator.record(
            signal,
            characterState: characterEngine.presentation.state.rawValue,
            displayIndex: context.displayIndex,
            cursorRegion: context.region,
            recentCharacterBeats: recentCharacterBeats
        )

        let localPlan = localProvider.immediateReaction(for: snapshot)
        let shouldPresent: Bool
        switch signal.kind {
        case .click, .rapidClick, .shortcutAttempt, .keyboardActivity:
            shouldPresent = true
        case .mouseMovement, .scroll:
            shouldPresent = waking || (signal.timestamp >= messageDeadline && signal.timestamp >= changeDeadline)
        }

        if shouldPresent {
            let preservingMessage = signal.timestamp < messageDeadline
            lastStateChangeAt = signal.timestamp
            characterEngine.apply(localPlan, near: signal.globalLocation, preservingMessage: preservingMessage)
            remember(localPlan)
            if preservingMessage {
                deferMessage(.reaction(localPlan))
            } else {
                cancelPendingMessage()
                lastMessageChangeAt = signal.timestamp
            }
        }
        scheduleRest(at: signal.timestamp.addingTimeInterval(restInterval))

        let currentConfiguration = configuration()
        guard currentConfiguration.enabled, let apiKey = currentConfiguration.apiKey else {
            cancelJevEvaluation()
            discardQueuedJevMessage()
            director.markLocalOnly()
            return
        }

        // Any newer signal invalidates a queued cloud decision, even if movement
        // was gated. A local candidate remains useful until it can be read.
        discardQueuedJevMessage()
        latestSnapshot = snapshotForJev(from: snapshot)
        latestLocation = signal.globalLocation
        quietDeadline = Date().addingTimeInterval(Double(quietPeriodNanoseconds) / 1_000_000_000)
        director.markWaiting()

        if jevRequestInFlight {
            cancelJevEvaluation()
            quietDeadline = Date().addingTimeInterval(Double(quietPeriodNanoseconds) / 1_000_000_000)
        }
        scheduleJevEvaluation(for: sessionID, apiKey: apiKey)
    }

    public func pointToAuthentication() {
        guard isSessionActive else { return }
        eventSequence += 1
        cancelJevEvaluation()
        cancelPendingMessage()
        director.markLocalOnly()
        isResting = false
        let now = Date()
        let preservingMessage = now < messageDeadline
        characterEngine.pointToAuthentication(preservingMessage: preservingMessage)
        lastStateChangeAt = now
        if preservingMessage {
            deferMessage(.authentication)
        } else {
            lastMessageChangeAt = now
        }
        // Failed authentication resumes interception without sending us a signal.
        // Keep the rest timer alive throughout that path.
        scheduleRest(at: now.addingTimeInterval(restInterval))
    }

    public func endSession() {
        isSessionActive = false
        cancelJevEvaluation()
        cancelPendingMessage()
        cancelRest()
        latestSnapshot = nil
        latestLocation = nil
        recentCharacterBeats.removeAll(keepingCapacity: true)
        sessionID = UUID()
        director.markLocalOnly()
    }

    private func deferMessage(_ candidate: PendingMessage) {
        pendingMessage = candidate
        guard messageTask == nil else { return }
        let taskID = UUID()
        messageTaskID = taskID
        messageTask = Task { [weak self] in
            do {
                while let self, self.messageTaskID == taskID, self.isSessionActive, !self.isResting {
                    let remaining = self.messageDeadline.timeIntervalSinceNow
                    if remaining > 0 {
                        try await Task.sleep(nanoseconds: UInt64(min(remaining, 60) * 1_000_000_000))
                        try Task.checkCancellation()
                        continue
                    }
                    self.publishPendingMessage(at: Date())
                    return
                }
            } catch {
                // Cancellation discards superseded dialogue without publishing it.
            }
        }
    }

    private func publishPendingMessage(at date: Date) {
        guard let candidate = pendingMessage else { return }
        if case let .reaction(plan, _) = candidate, plan.source == .jev {
            let currentConfiguration = configuration()
            if !currentConfiguration.enabled || currentConfiguration.apiKey == nil {
                discardQueuedJevMessage()
                director.markLocalOnly()
                publishPendingMessage(at: date)
                return
            }
        }
        cancelPendingMessage()
        switch candidate {
        case let .reaction(plan, _):
            characterEngine.publishMessage(for: plan)
            if plan.source == .jev {
                remember(plan)
                director.markApplied(plan)
            }
        case .authentication:
            characterEngine.publishAuthenticationMessage()
        }
        lastMessageChangeAt = date
    }

    private func discardQueuedJevMessage() {
        guard case let .reaction(plan, fallback) = pendingMessage, plan.source == .jev else { return }
        cancelPendingMessage()
        if let fallback {
            deferMessage(.reaction(fallback))
        }
    }

    private func scheduleRest(at deadline: Date) {
        cancelRest()
        let taskID = UUID()
        restTaskID = taskID
        restTask = Task { [weak self] in
            do {
                while let self, self.restTaskID == taskID, self.isSessionActive {
                    let remaining = max(deadline, self.messageDeadline).timeIntervalSinceNow
                    if remaining > 0 {
                        try await Task.sleep(nanoseconds: UInt64(min(remaining, 60) * 1_000_000_000))
                        try Task.checkCancellation()
                        continue
                    }
                    if self.pendingMessage != nil {
                        // A due message wins a tie with rest and receives its own
                        // full reading window, regardless of timer scheduling order.
                        self.publishPendingMessage(at: Date())
                        continue
                    }
                    self.cancelRest()
                    self.cancelPendingMessage()
                    self.cancelJevEvaluation()
                    self.latestSnapshot = nil
                    self.latestLocation = nil
                    self.aggregator.clearRecentActivity()
                    self.recentCharacterBeats.removeAll(keepingCapacity: true)
                    self.isResting = true
                    self.characterEngine.rest()
                    self.director.markLocalOnly()
                    return
                }
            } catch {
                // A newer input or session owns the replacement timer.
            }
        }
    }

    private func cancelPendingMessage() {
        messageTask?.cancel()
        messageTask = nil
        messageTaskID = nil
        pendingMessage = nil
    }

    private func cancelRest() {
        restTask?.cancel()
        restTask = nil
        restTaskID = nil
    }

    private func cancelJevEvaluation() {
        pendingTask?.cancel()
        pendingTask = nil
        pendingTaskID = nil
        jevRequestInFlight = false
        quietDeadline = nil
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
                          self.eventSequence == requestSequence,
                          self.pendingTaskID == taskID,
                          self.isSessionActive,
                          !self.isResting,
                          self.configuration().enabled,
                          self.configuration().apiKey == apiKey
                    else {
                        self.finishTask(taskID)
                        return
                    }

                    let now = Date()
                    if now < self.messageDeadline {
                        let localFallback: ReactionPlan?
                        if case let .reaction(pending, fallback) = self.pendingMessage {
                            localFallback = pending.source == .local ? pending : fallback
                        } else {
                            localFallback = nil
                        }
                        self.deferMessage(.reaction(plan, localFallback: localFallback))
                    } else {
                        self.cancelPendingMessage()
                        if now >= self.changeDeadline {
                            self.characterEngine.apply(plan, near: location)
                            self.lastStateChangeAt = now
                        } else {
                            self.characterEngine.publishMessage(for: plan)
                        }
                        self.lastMessageChangeAt = now
                        self.remember(plan)
                        self.director.markApplied(plan)
                    }
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
            recentCharacterBeats: recentCharacterBeats,
            movementGestureDuration: snapshot.movementGestureDuration
        )
    }
}
