import XCTest
@testable import Typeleast

final class LiveTextInsertionManagerTests: XCTestCase {
    func testAppendOnlyInsertionReturnsInitialText() {
        XCTAssertEqual(
            LiveTextInsertionManager.appendOnlyInsertion(from: "", to: "你好"),
            "你好"
        )
    }

    func testAppendOnlyInsertionReturnsOnlyNewSuffix() {
        XCTAssertEqual(
            LiveTextInsertionManager.appendOnlyInsertion(from: "你好", to: "你好世界"),
            "世界"
        )
    }

    func testAppendOnlyInsertionSkipsPartialRewrite() {
        XCTAssertNil(
            LiveTextInsertionManager.appendOnlyInsertion(from: "你好试", to: "你好是")
        )
    }

    func testAppendOnlyInsertionSkipsShorterText() {
        XCTAssertNil(
            LiveTextInsertionManager.appendOnlyInsertion(from: "你好世界", to: "你好")
        )
    }
}
