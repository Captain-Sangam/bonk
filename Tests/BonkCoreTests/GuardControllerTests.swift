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
    private func makeFixture() -> Fixture {
        let suiteName = "BonkCoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(true, forKey: "keepAwake")
        let settings = SettingsStore(defaults: defaults)
        let input = FakeInputInterceptor()
        let awake = FakeAwakeManager()
        let overlay = FakeOverlayManager()
        let authentication = FakeAuthenticationManager()
        let reactions = FakeReactionController()
        let character = FakeCharacterPresenter()
        let controller = GuardController(
            settings: settings,
            inputInterceptor: input,
            awakeManager: awake,
            overlayManager: overlay,
            authenticationManager: authentication,
            reactionController: reactions,
            characterEngine: character
        )

        return Fixture(
            controller: controller,
            input: input,
            awake: awake,
            overlay: overlay,
            reactions: reactions,
            authentication: authentication
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
    var showError: Error?

    func show() throws {
        showCount += 1
        if let showError { throw showError }
    }
    func setCapturingInput(_ capture: Bool) { isCapturingInput = capture }
    func hide() { hideCount += 1 }
}

private final class FakeAuthenticationManager: OwnerAuthenticating {
    private(set) var callCount = 0
    var onAuthenticate: (() -> Void)?

    func authenticateOwner() async throws {
        callCount += 1
        onAuthenticate?()
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
