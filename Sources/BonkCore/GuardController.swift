import Combine
import Foundation

@MainActor
public final class GuardController: ObservableObject {
    @Published public private(set) var status: GuardStatus = .idle
    @Published public private(set) var lastError: String?

    public var isGuarding: Bool { status.isGuarding }

    private let settings: SettingsStore
    private let inputInterceptor: InputIntercepting
    private let awakeManager: AwakeManaging
    private let overlayManager: OverlayManaging
    private let authenticationManager: OwnerAuthenticating
    private let reactionController: ReactionControlling
    private let characterEngine: CharacterPresenting

    private var authenticationTask: Task<Void, Never>?
    private var returnToArmedTask: Task<Void, Never>?

    public init(
        settings: SettingsStore,
        inputInterceptor: InputIntercepting,
        awakeManager: AwakeManaging,
        overlayManager: OverlayManaging,
        authenticationManager: OwnerAuthenticating,
        reactionController: ReactionControlling,
        characterEngine: CharacterPresenting
    ) {
        self.settings = settings
        self.inputInterceptor = inputInterceptor
        self.awakeManager = awakeManager
        self.overlayManager = overlayManager
        self.authenticationManager = authenticationManager
        self.reactionController = reactionController
        self.characterEngine = characterEngine

        inputInterceptor.onSignal = { [weak self] signal in
            Task { @MainActor in self?.handle(signal) }
        }
        inputInterceptor.onAuthenticationGesture = { [weak self] in
            Task { @MainActor in self?.beginOwnerAuthentication() }
        }
        inputInterceptor.onFailure = { [weak self] error in
            Task { @MainActor in self?.failOpen(error.localizedDescription) }
        }
        overlayManager.onFailure = { [weak self] message in
            Task { @MainActor in self?.failOpen(message) }
        }
    }

    public func activate() {
        guard status == .idle else { return }
        lastError = nil
        reactionController.beginSession()

        do {
            try overlayManager.show()
            if settings.keepAwake {
                awakeManager.start()
            }
            try inputInterceptor.start(promptForPermission: true)
            status = .armed
        } catch {
            cleanupGuardResources()
            lastError = error.localizedDescription
            if error as? BonkError == .accessibilityPermissionMissing {
                InputInterceptor.openAccessibilitySettings()
            }
        }
    }

    public func clearError() {
        lastError = nil
    }

    public func shutdown() {
        authenticationTask?.cancel()
        returnToArmedTask?.cancel()
        cleanupGuardResources()
        status = .idle
    }

    private func handle(_ signal: InteractionSignal) {
        guard status == .armed || status == .reacting else { return }
        status = .reacting
        reactionController.handle(signal)

        returnToArmedTask?.cancel()
        returnToArmedTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 550_000_000)
            guard let self, self.status == .reacting else { return }
            self.status = .armed
        }
    }

    private func beginOwnerAuthentication() {
        guard status == .armed || status == .reacting, authenticationTask == nil else { return }
        authenticationTask = Task { [weak self] in
            guard let self else { return }
            do {
                self.reactionController.pointToAuthentication()
                try await Task.sleep(nanoseconds: 450_000_000)
                try Task.checkCancellation()

                // Password fallback must be able to receive keyboard input. The
                // transparent overlay captures the desktop while macOS owns the
                // authentication sheet above it.
                self.inputInterceptor.stop()
                self.overlayManager.setCapturingInput(true)
                self.status = .authenticating

                try await self.authenticationManager.authenticateOwner()
                try Task.checkCancellation()
                await self.completeSuccessfulAuthentication()
            } catch is CancellationError {
                return
            } catch {
                self.lastError = error.localizedDescription
                self.resumeAfterAuthenticationFailure()
            }
        }
    }

    private func completeSuccessfulAuthentication() async {
        characterEngine.celebrate()
        try? await Task.sleep(nanoseconds: 600_000_000)
        cleanupGuardResources()
        status = .idle
        authenticationTask = nil
    }

    private func resumeAfterAuthenticationFailure() {
        overlayManager.setCapturingInput(false)
        do {
            try inputInterceptor.start(promptForPermission: false)
            status = .armed
            authenticationTask = nil
        } catch {
            failOpen(error.localizedDescription)
        }
    }

    private func failOpen(_ message: String) {
        authenticationTask?.cancel()
        returnToArmedTask?.cancel()
        cleanupGuardResources()
        status = .idle
        lastError = message
    }

    private func cleanupGuardResources() {
        inputInterceptor.stop()
        awakeManager.stop()
        overlayManager.hide()
        reactionController.endSession()
        authenticationTask = nil
        returnToArmedTask = nil
    }
}
