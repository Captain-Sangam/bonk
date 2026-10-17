import Foundation

public protocol InputIntercepting: AnyObject {
    var onSignal: ((InteractionSignal) -> Void)? { get set }
    var onAuthenticationGesture: (() -> Void)? { get set }
    var onFailure: ((BonkError) -> Void)? { get set }
    var isRunning: Bool { get }

    func start(promptForPermission: Bool) throws
    func stop()
}

public protocol AwakeManaging: AnyObject {
    func start()
    func stop()
}

@MainActor
public protocol OverlayManaging: AnyObject {
    var onFailure: ((String) -> Void)? { get set }

    func show(mode: BonkMode) throws
    func setCapturingInput(_ capture: Bool)
    func hide()
}

/// Captures a single still from the camera on a genuine failed unlock attempt.
public protocol IntrusionCapturing: AnyObject {
    /// Request camera access (called when the user enables the monitor, while idle).
    func requestAccess() async -> Bool
    /// Whether the camera is currently authorized, for surfacing status in Settings.
    var isAuthorized: Bool { get }
    /// Capture one photo; returns true if a photo was saved. Fire-and-forget: never blocks unlock.
    @discardableResult
    func captureIntrusion() async -> Bool
    /// Where saved intrusion photos live, for "Show in Finder".
    var captureDirectory: URL { get }
}

public protocol OwnerAuthenticating: AnyObject {
    func authenticateOwner() async throws
}

@MainActor
public protocol ReactionControlling: AnyObject {
    func beginSession()
    func handle(_ signal: InteractionSignal)
    func pointToAuthentication()
    func endSession()
}

@MainActor
public protocol CharacterPresenting: AnyObject {
    func celebrate()
}
