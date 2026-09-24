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

    func show() throws
    func setCapturingInput(_ capture: Bool)
    func hide()
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
