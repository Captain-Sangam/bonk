import Foundation
import XCTest
@testable import BonkCore

final class GuardControllerTests: XCTestCase {
    @MainActor
    func testActivationStartsEveryGuardResourceAndShutdownCleansUp() {
        let fixture = makeFixture()

        fixture.controller.activate()

        XCTAssertEqual(fixture.controller.status, .armed)
        XCTAssertEqual(fixture.input.startCount, 1)
        XCTAssertTrue(fixture.input.isRunning)
        XCTAssertEqual(fixture.awake.startCount, 1)
        XCTAssertEqual(fixture.overlay.showCount, 1)
        XCTAssertEqual(fixture.reactions.beginCount, 1)

        fixture.controller.shutdown()

        XCTAssertEqual(fixture.controller.status, .idle)
        XCTAssertFalse(fixture.input.isRunning)
        XCTAssertGreaterThanOrEqual(fixture.input.stopCount, 1)
        XCTAssertEqual(fixture.awake.stopCount, 1)
        XCTAssertEqual(fixture.overlay.hideCount, 1)
        XCTAssertEqual(fixture.reactions.endCount, 1)
    }

    @MainActor
    func testInputInterceptorFailureImmediatelyFailsOpen() async {
        let fixture = makeFixture()
        fixture.controller.activate()

        fixture.input.onFailure?(.eventTapDisabled)
        await Task.yield()

        XCTAssertEqual(fixture.controller.status, .idle)
        XCTAssertFalse(fixture.input.isRunning)
        XCTAssertEqual(fixture.awake.stopCount, 1)
        XCTAssertEqual(fixture.overlay.hideCount, 1)
        XCTAssertEqual(fixture.reactions.endCount, 1)
        XCTAssertNotNil(fixture.controller.lastError)
    }

    @MainActor
    func testFailedInputStartupRollsBackPreviouslyStartedResources() {
        let fixture = makeFixture()
        fixture.input.startError = BonkError.eventTapCreationFailed

        fixture.controller.activate()

        XCTAssertEqual(fixture.controller.status, .idle)
        XCTAssertFalse(fixture.input.isRunning)
        XCTAssertEqual(fixture.awake.stopCount, 1)
        XCTAssertEqual(fixture.overlay.hideCount, 1)
        XCTAssertEqual(fixture.reactions.endCount, 1)
        XCTAssertEqual(fixture.controller.lastError, BonkError.eventTapCreationFailed.localizedDescription)
    }

    @MainActor
    func testFailedOverlayStartupNeverStartsInputAndRollsBackSession() {
        let fixture = makeFixture()
        fixture.overlay.showError = BonkError.overlayUnavailable("No display")

        fixture.controller.activate()

        XCTAssertEqual(fixture.controller.status, .idle)
        XCTAssertEqual(fixture.input.startCount, 0)
        XCTAssertFalse(fixture.input.isRunning)
        XCTAssertEqual(fixture.awake.startCount, 0)
        XCTAssertEqual(fixture.overlay.hideCount, 1)
        XCTAssertEqual(fixture.reactions.endCount, 1)
        XCTAssertNotNil(fixture.controller.lastError)
    }

    @MainActor
    func testOrdinaryInputNeverStartsAuthentication() async {
        let fixture = makeFixture()
        fixture.controller.activate()

        fixture.input.onSignal?(InteractionSignal(kind: .keyboardActivity))
        fixture.input.onSignal?(InteractionSignal(kind: .click))
        await Task.yield()

        XCTAssertEqual(fixture.controller.status, .reacting)
        XCTAssertEqual(fixture.authentication.callCount, 0)
    }

    @MainActor
    func testDoubleEscapeGestureStartsAuthentication() async {
        let fixture = makeFixture()
        let authenticationStarted = expectation(description: "Owner authentication started")
        fixture.authentication.onAuthenticate = {
            authenticationStarted.fulfill()
        }
        fixture.controller.activate()

        fixture.input.onAuthenticationGesture?()
        await fulfillment(of: [authenticationStarted], timeout: 2.0)

        XCTAssertEqual(fixture.authentication.callCount, 1)
    }

    @MainActor
    func testRealReactionPacingAndRestSurviveAuthenticationFailure() async throws {
        let character = CharacterEngine { false }
        let reactions = ReactionController(characterEngine: character, director: JevDirectorMonitor(),
            displayInterval: 0.06, restInterval: 0.1, configuration: { (false, nil) })
        let input = FakeInputInterceptor()
        let authentication = FakeAuthenticationManager()
        authentication.error = BonkError.authenticationFailed("Cancelled")
        let defaults = UserDefaults(suiteName: "BonkAuthResume.\(UUID())")!
        let guardController = GuardController(settings: SettingsStore(defaults: defaults), inputInterceptor: input,
            awakeManager: FakeAwakeManager(), overlayManager: FakeOverlayManager(),
            authenticationManager: authentication, reactionController: reactions, characterEngine: character)
        guardController.activate()
        defer { guardController.shutdown() }
        input.onAuthenticationGesture?()
        for _ in 0..<100 {
            if authentication.callCount == 1 && guardController.status == .armed { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(authentication.callCount, 1)
        XCTAssertEqual(guardController.status, .armed)
        XCTAssertEqual(input.startCount, 2)
        XCTAssertTrue(input.isRunning)
        XCTAssertEqual(character.presentation.state, .sleeping)
        XCTAssertNil(character.presentation.message)
        input.onSignal?(InteractionSignal(kind: .mouseMovement))
        await Task.yield()
        XCTAssertEqual(character.presentation.state, .notice)
        let text = character.presentation.message
        input.onSignal?(InteractionSignal(kind: .keyboardActivity))
        await Task.yield()
        XCTAssertEqual(character.presentation.state, .annoyed)
        XCTAssertEqual(character.presentation.message, text)
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(character.presentation.state, .sleeping)
        XCTAssertNil(character.presentation.message)
    }

    @MainActor
    func testCameraCapturesOnlyOnGenuineFailure() async throws {
        // Genuine rejection with the monitor on → one capture, one counted attempt.
        let failed = makeFixture(cameraMonitorEnabled: true)
        failed.authentication.error = BonkError.authenticationFailed("nope")
        failed.controller.activate()
        failed.input.onAuthenticationGesture?()
        try await poll { failed.controller.failedAttempts == 1 && failed.camera.captureCount == 1 }
        XCTAssertEqual(failed.controller.failedAttempts, 1)
        XCTAssertEqual(failed.camera.captureCount, 1)

        // A "Keep Bonk On" cancel must NOT count or photograph.
        let cancelled = makeFixture(cameraMonitorEnabled: true)
        cancelled.authentication.error = BonkError.authenticationCancelled("Keep Bonk On")
        cancelled.controller.activate()
        cancelled.input.onAuthenticationGesture?()
        try await poll { cancelled.authentication.callCount == 1 && cancelled.controller.status == .armed }
        XCTAssertEqual(cancelled.controller.failedAttempts, 0)
        XCTAssertEqual(cancelled.camera.captureCount, 0)

        // Disabled monitor never captures, even on a genuine failure.
        let off = makeFixture(cameraMonitorEnabled: false)
        off.authentication.error = BonkError.authenticationFailed("nope")
        off.controller.activate()
        off.input.onAuthenticationGesture?()
        try await poll { off.authentication.callCount == 1 && off.controller.status == .armed }
        XCTAssertEqual(off.camera.captureCount, 0)
    }

    @MainActor
    func testFailedAttemptsResetOnActivate() async throws {
        let fixture = makeFixture(cameraMonitorEnabled: true)
        fixture.authentication.error = BonkError.authenticationFailed("nope")
        fixture.controller.activate()
        fixture.input.onAuthenticationGesture?()
        try await poll { fixture.controller.failedAttempts == 1 }
        fixture.controller.shutdown()
        fixture.controller.activate()
        XCTAssertEqual(fixture.controller.failedAttempts, 0)
    }

    @MainActor
    func testNonClassicModeSkipsReactionSession() {
        let fixture = makeFixture(mode: .screenOff)
        fixture.controller.activate()
        XCTAssertEqual(fixture.reactions.beginCount, 0)
        XCTAssertEqual(fixture.overlay.shownMode, .screenOff)
    }

    @MainActor
    private func poll(timeout: TimeInterval = 2.0, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    @MainActor
    private func makeFixture(mode: BonkMode = .classic, cameraMonitorEnabled: Bool = false) -> Fixture {
        let suiteName = "BonkCoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(true, forKey: "keepAwake")
        let settings = SettingsStore(defaults: defaults)
        settings.bonkMode = mode
        settings.cameraMonitorEnabled = cameraMonitorEnabled
        let input = FakeInputInterceptor()
        let awake = FakeAwakeManager()
        let overlay = FakeOverlayManager()
        let authentication = FakeAuthenticationManager()
        let reactions = FakeReactionController()
        let character = FakeCharacterPresenter()
        let camera = FakeIntrusionCamera()
        let controller = GuardController(
            settings: settings,
            inputInterceptor: input,
            awakeManager: awake,
            overlayManager: overlay,
            authenticationManager: authentication,
            reactionController: reactions,
            characterEngine: character,
            cameraMonitor: camera
        )

        return Fixture(
            controller: controller,
            input: input,
            awake: awake,
            overlay: overlay,
            reactions: reactions,
            authentication: authentication,
            camera: camera
        )
    }
}

@MainActor
private struct Fixture {
    let controller: GuardController
    let input: FakeInputInterceptor
    let awake: FakeAwakeManager
    let overlay: FakeOverlayManager
    let reactions: FakeReactionController
    let authentication: FakeAuthenticationManager
    let camera: FakeIntrusionCamera
}

private final class FakeInputInterceptor: InputIntercepting {
    var onSignal: ((InteractionSignal) -> Void)?
    var onAuthenticationGesture: (() -> Void)?
    var onFailure: ((BonkError) -> Void)?
    private(set) var isRunning = false
    var startError: Error?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start(promptForPermission: Bool) throws {
        startCount += 1
        if let startError { throw startError }
        isRunning = true
    }

    func stop() {
        stopCount += 1
        isRunning = false
    }
}

private final class FakeAwakeManager: AwakeManaging {
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
}

@MainActor
private final class FakeOverlayManager: OverlayManaging {
    var onFailure: ((String) -> Void)?
    private(set) var showCount = 0
    private(set) var hideCount = 0
    private(set) var isCapturingInput = false
    private(set) var shownMode: BonkMode?
    var showError: Error?

    func show(mode: BonkMode) throws {
        showCount += 1
        shownMode = mode
        if let showError { throw showError }
    }
    func setCapturingInput(_ capture: Bool) { isCapturingInput = capture }
    func hide() { hideCount += 1 }
}

private final class FakeAuthenticationManager: OwnerAuthenticating {
    private(set) var callCount = 0
    var onAuthenticate: (() -> Void)?
    var error: Error?

    func authenticateOwner() async throws {
        callCount += 1
        onAuthenticate?()
        if let error { throw error }
    }
}

@MainActor
private final class FakeReactionController: ReactionControlling {
    private(set) var beginCount = 0
    private(set) var endCount = 0

    func beginSession() { beginCount += 1 }
    func handle(_ signal: InteractionSignal) {}
    func pointToAuthentication() {}
    func endSession() { endCount += 1 }
}

@MainActor
private final class FakeCharacterPresenter: CharacterPresenting {
    func celebrate() {}
}

private final class FakeIntrusionCamera: IntrusionCapturing {
    let captureDirectory = FileManager.default.temporaryDirectory
    var isAuthorized: Bool { true }
    func requestAccess() async -> Bool { true }

    private let lock = NSLock()
    private var count = 0
    var captureCount: Int { lock.lock(); defer { lock.unlock() }; return count }

    @discardableResult
    func captureIntrusion() async -> Bool {
        lock.lock(); count += 1; lock.unlock()
        return true
    }
}
