import AppKit
import Combine
import Foundation

@MainActor
public final class AppModel: ObservableObject {
    public let settings: SettingsStore
    public let characterEngine: CharacterEngine
    public let guardController: GuardController

    private let shortcutMonitor = ShortcutMonitor()
    private var cancellables: Set<AnyCancellable> = []
    private var hasStarted = false

    public init() {
        let settings = SettingsStore()
        let characterEngine = CharacterEngine { settings.soundsEnabled }
        let reactionController = ReactionController(characterEngine: characterEngine) {
            (settings.aiReactionsEnabled, settings.jevAPIKey)
        }
        let overlayManager = OverlayManager(characterEngine: characterEngine)

        self.settings = settings
        self.characterEngine = characterEngine
        guardController = GuardController(
            settings: settings,
            inputInterceptor: InputInterceptor(),
            awakeManager: AwakeManager(),
            overlayManager: overlayManager,
            authenticationManager: AuthenticationManager(),
            reactionController: reactionController,
            characterEngine: characterEngine
        )
    }

    public func start() {
        guard !hasStarted else { return }
        hasStarted = true
        configureShortcut(key: settings.shortcutKey)

        settings.$shortcutKey
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] key in
                self?.configureShortcut(key: key)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.shutdown() }
            .store(in: &cancellables)
    }

    public func toggleGuard() {
        if guardController.isGuarding {
            guardController.requestOwnerAuthentication()
        } else {
            guardController.activate()
        }
    }

    public func shutdown() {
        guardController.shutdown()
        shortcutMonitor.stop()
        cancellables.removeAll()
    }

    private func configureShortcut(key: String) {
        shortcutMonitor.start(key: key) { [weak self] in
            self?.toggleGuard()
        }
    }
}
