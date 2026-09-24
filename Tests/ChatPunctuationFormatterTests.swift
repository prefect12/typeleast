import XCTest
@testable import Typeleast

final class ChatPunctuationFormatterTests: XCTestCase {
    private func format(_ text: String) -> String {
        ChatPunctuationFormatter.removingSentencePeriods(from: text)
    }

    func testRemovesTrailingChinesePeriod() {
        XCTAssertEqual(format("我马上到。"), "我马上到")
    }

    func testReplacesPeriodsBetweenSentencesWithSpace() {
        XCTAssertEqual(format("好的。明天见。"), "好的 明天见")
    }

    func testRemovesTrailingEnglishPeriod() {
        XCTAssertEqual(format("Sounds good."), "Sounds good")
    }

    func testKeepsQuestionAndExclamationMarks() {
        XCTAssertEqual(format("你到了吗？太好了！"), "你到了吗？太好了！")
        XCTAssertEqual(format("Really?"), "Really?")
    }

    func testKeepsEllipsesAndDecimals() {
        XCTAssertEqual(format("我想想..."), "我想想...")
        XCTAssertEqual(format("我想想……"), "我想想……")
        XCTAssertEqual(format("版本是 2.1"), "版本是 2.1")
    }

    func testHandlesEachLineSeparately() {
        XCTAssertEqual(format("第一行。\n第二行。"), "第一行\n第二行")
    }

    func testLeavesTextWithoutPeriodsUnchanged() {
        XCTAssertEqual(format("收到"), "收到")
        XCTAssertEqual(format(""), "")
    }
}
