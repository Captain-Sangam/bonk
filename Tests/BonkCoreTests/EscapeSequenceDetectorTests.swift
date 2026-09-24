import XCTest
@testable import BonkCore

final class EscapeSequenceDetectorTests: XCTestCase {
    func testTwoEscapePressesWithinWindowTriggerOnce() {
        var detector = EscapeSequenceDetector()

        XCTAssertFalse(detector.register(keyCode: 53, isRepeat: false, at: 10))
        XCTAssertTrue(detector.register(keyCode: 53, isRepeat: false, at: 10.4))
        XCTAssertFalse(detector.register(keyCode: 53, isRepeat: false, at: 10.5))
    }

    func testHeldEscapeDoesNotTrigger() {
        var detector = EscapeSequenceDetector()

        XCTAssertFalse(detector.register(keyCode: 53, isRepeat: false, at: 10))
        XCTAssertFalse(detector.register(keyCode: 53, isRepeat: true, at: 10.1))
    }

    func testSlowOrInterruptedEscapeSequenceDoesNotTrigger() {
        var detector = EscapeSequenceDetector()

        XCTAssertFalse(detector.register(keyCode: 53, isRepeat: false, at: 10))
        XCTAssertFalse(detector.register(keyCode: 53, isRepeat: false, at: 11))
        XCTAssertFalse(detector.register(keyCode: 12, isRepeat: false, at: 11.1))
        XCTAssertFalse(detector.register(keyCode: 53, isRepeat: false, at: 11.2))
    }
}
