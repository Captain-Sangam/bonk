import CoreGraphics
import XCTest
@testable import BonkCore

final class InputInterceptorTests: XCTestCase {
    func testMaskIncludesTrackpadGestureTypes() {
        for type in [29, 30, 31] {
            XCTAssertNotEqual(InputInterceptor.eventMask & (CGEventMask(1) << CGEventMask(type)), 0, "type \(type)")
        }
    }

    func testPassThroughLetsEscapeReachTheUnlockSheet() {
        let interceptor = InputInterceptor()
        var signals = 0
        var gestures = 0
        interceptor.onSignal = { _ in signals += 1 }
        interceptor.onAuthenticationGesture = { gestures += 1 }
        interceptor.allowsOwnerInput = true

        for _ in 0..<2 {
            let escape = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)!
            XCTAssertNotNil(interceptor.handle(type: .keyDown, event: escape))
        }

        XCTAssertEqual(signals, 0)
        XCTAssertEqual(gestures, 0)
    }

    func testDockGestureIsDroppedInBothModes() {
        let interceptor = InputInterceptor()
        let dockControl = CGEventType(rawValue: 30)!

        XCTAssertNil(interceptor.handle(type: dockControl, event: CGEvent(source: nil)!))
        interceptor.allowsOwnerInput = true
        XCTAssertNil(interceptor.handle(type: dockControl, event: CGEvent(source: nil)!))
    }

    func testTapDisabledFailsOpenOnlyOutsidePassThrough() {
        let interceptor = InputInterceptor()
        let reported = expectation(description: "Failure reported")
        reported.isInverted = true
        interceptor.onFailure = { _ in reported.fulfill() }
        interceptor.allowsOwnerInput = true

        _ = interceptor.handle(type: .tapDisabledByUserInput, event: CGEvent(source: nil)!)
        wait(for: [reported], timeout: 0.2)

        let reportedOutside = expectation(description: "Failure reported outside pass-through")
        interceptor.onFailure = { _ in reportedOutside.fulfill() }
        interceptor.allowsOwnerInput = false
        _ = interceptor.handle(type: .tapDisabledByUserInput, event: CGEvent(source: nil)!)
        wait(for: [reportedOutside], timeout: 1.0)
        XCTAssertFalse(interceptor.isRunning)
    }
}
