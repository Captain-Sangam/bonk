import Foundation

@MainActor
public final class ReactionController: ReactionControlling {
    public typealias Configuration = (enabled: Bool, apiKey: String?)

    private let characterEngine: CharacterEngine
    private let configuration: () -> Configuration
    private let localProvider = LocalReactionProvider()
    private var aggregator = InteractionAggregator()
    private var sessionID = UUID()
    private var eventSequence = 0
    private var pendingTask: Task<Void, Never>?

    public init(
        characterEngine: CharacterEngine,
        configuration: @escaping () -> Configuration
    ) {
        self.characterEngine = characterEngine
        self.configuration = configuration
    }

    public func beginSession() {
        pendingTask?.cancel()
        sessionID = UUID()
        eventSequence = 0
        aggregator.reset()
        characterEngine.reset()
    }

    public func handle(_ signal: InteractionSignal) {
        eventSequence += 1
        let currentSequence = eventSequence
        let currentSession = sessionID
        let context = characterEngine.context(for: signal.globalLocation)
        let snapshot = aggregator.record(
            signal,
            characterState: characterEngine.presentation.state.rawValue,
            displayIndex: context.displayIndex,
            cursorRegion: context.region
        )

        characterEngine.apply(localProvider.immediateReaction(for: snapshot), near: signal.globalLocation)

        let currentConfiguration = configuration()
        guard currentConfiguration.enabled, let apiKey = currentConfiguration.apiKey else { return }

        pendingTask?.cancel()
        pendingTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
                try Task.checkCancellation()
                let provider = JevReactionProvider(apiKey: apiKey)
                let plan = try await provider.reaction(for: snapshot)
                try Task.checkCancellation()

                guard let self,
                      self.sessionID == currentSession,
                      self.eventSequence == currentSequence
                else {
                    return
                }

                self.characterEngine.apply(plan, near: signal.globalLocation)
            } catch {
                // The local reaction is already visible. Network and model failures
                // are deliberately silent and never affect Guard Mode.
            }
        }
    }

    public func pointToAuthentication() {
        pendingTask?.cancel()
        characterEngine.pointToAuthentication()
    }

    public func endSession() {
        pendingTask?.cancel()
        pendingTask = nil
        sessionID = UUID()
    }
}
