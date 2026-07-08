import XCTest
@testable import Typeleast

final class LiveTextInsertionManagerTests: XCTestCase {
    func testEditPlanReturnsInitialText() {
        XCTAssertEqual(
            LiveTextInsertionManager.editPlan(from: "", to: "你好"),
            LiveTextEditPlan(deleteCount: 0, insertText: "你好")
        )
    }

    func testEditPlanReturnsOnlyNewSuffix() {
        XCTAssertEqual(
            LiveTextInsertionManager.editPlan(from: "你好", to: "你好世界"),
            LiveTextEditPlan(deleteCount: 0, insertText: "世界")
        )
    }

    func testEditPlanReplacesPartialRewrite() {
        XCTAssertEqual(
            LiveTextInsertionManager.editPlan(from: "你好试", to: "你好是"),
            LiveTextEditPlan(deleteCount: 1, insertText: "是")
        )
    }

    func testEditPlanDeletesShorterText() {
        XCTAssertEqual(
            LiveTextInsertionManager.editPlan(from: "你好世界", to: "你好"),
            LiveTextEditPlan(deleteCount: 2, insertText: "")
        )
    }

    func testEditPlanReplacesSuffixOnlyPartialWithFullChineseText() {
        XCTAssertEqual(
            LiveTextInsertionManager.editPlan(from: "输入", to: "测试语音输入"),
            LiveTextEditPlan(deleteCount: 2, insertText: "测试语音输入")
        )
    }

    func testEditPlanRestoresMissingLeadingChineseText() {
        XCTAssertEqual(
            LiveTextInsertionManager.editPlan(from: ",测试语音输入。", to: "你好,测试语音输入。"),
            LiveTextEditPlan(deleteCount: 8, insertText: "你好,测试语音输入。")
        )
    }
}
