import AppKit
import Carbon.HIToolbox
import Combine
import Foundation

@MainActor
public final class AppModel: ObservableObject {
    public let settings: SettingsStore
    public let characterEngine: CharacterEngine
    public let jevDirector: JevDirectorMonitor
    public let guardController: GuardController
    public let camera: IntrusionCamera

    /// Why the saved shortcut is not registered, shown under the Settings shortcut row.
    @Published public private(set) var shortcutError: String?

    private lazy var shortcutMonitor = ShortcutMonitor { [weak self] in self?.toggleGuard() }
    private var cancellables: Set<AnyCancellable> = []
    private var hasStarted = false

    public init() {
        let settings = SettingsStore()
        let characterEngine = CharacterEngine { settings.soundsEnabled }
        let jevDirector = JevDirectorMonitor()
        let reactionController = ReactionController(
            characterEngine: characterEngine,
            director: jevDirector
        ) {
            (settings.aiReactionsEnabled, settings.jevAPIKey)
        }
        let overlayManager = OverlayManager(
            characterEngine: characterEngine,
            agentPatterns: { settings.agentPatternList },
            awayName: { settings.awayName }
        )

        let camera = IntrusionCamera()

        self.settings = settings
        self.characterEngine = characterEngine
        self.jevDirector = jevDirector
        self.camera = camera
        guardController = GuardController(
            settings: settings,
            inputInterceptor: InputInterceptor(),
            awakeManager: AwakeManager(),
            overlayManager: overlayManager,
            authenticationManager: AuthenticationManager(),
            reactionController: reactionController,
            characterEngine: characterEngine,
            cameraMonitor: camera
        )
    }

    public func start() {
        guard !hasStarted else { return }
        hasStarted = true
        let status = shortcutMonitor.register(settings.shortcut)
        shortcutError = status == noErr ? nil : Self.registrationError(settings.shortcut, status)

        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.shutdown() }
            .store(in: &cancellables)
    }

    public func toggleGuard() {
        guard !guardController.isGuarding else { return }
        guardController.activate()
    }

    public func shutdown() {
        guardController.shutdown()
        shortcutMonitor.stop()
        cancellables.removeAll()
    }

    /// Registers `shortcut` first and saves it only on success; on failure the previous one stays.
    public func setShortcut(_ shortcut: Shortcut) {
        let previous = settings.shortcut
        let status = shortcutMonitor.register(shortcut)
        guard status == noErr else {
            _ = shortcutMonitor.register(previous)
            shortcutError = Self.registrationError(shortcut, status)
            return
        }
        settings.shortcut = shortcut
        shortcutError = nil
    }

    public func suspendShortcut() {
        shortcutMonitor.suspend()
    }

    public func resumeShortcut() {
        shortcutMonitor.resume()
    }

    private static func registrationError(_ shortcut: Shortcut, _ status: OSStatus) -> String {
        if status == eventHotKeyExistsErr {
            return "\(shortcut.displayString) is already used by another app."
        }
        return "\(shortcut.displayString) could not be registered (error \(status))."
    }
}
