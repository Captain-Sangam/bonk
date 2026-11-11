import CoreGraphics
import XCTest
@testable import BonkCore

final class InputInterceptorTests: XCTestCase {
    func testMaskIncludesTrackpadGestureTypes() {
        for type in [29, 30, 31] {
            XCTAssertNotEqual(InputInterceptor.eventMask & (CGEventMask(1) << CGEventMask(type)), 0, "type \(type)")
        }
    }
}
