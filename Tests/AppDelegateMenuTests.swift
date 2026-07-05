import AppKit
import XCTest
@testable import AudioWhisper

final class AppDelegateMenuTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "appLanguage")
        super.tearDown()
    }

    @MainActor
    func testStatusMenuVisibleItemsAreOrderedForChinese() {
        LanguageManager.shared.current = .chinese

        let titles = visibleMenuTitles(from: AppDelegate().makeStatusMenu())

        XCTAssertEqual(titles, ["录音", "转录音频文件...", "设置", "退出"])
        XCTAssertFalse(titles.contains("仪表盘..."))
        XCTAssertFalse(titles.contains("帮助"))
    }

    @MainActor
    func testStatusMenuVisibleItemsAreOrderedForEnglish() {
        LanguageManager.shared.current = .english

        let titles = visibleMenuTitles(from: AppDelegate().makeStatusMenu())

        XCTAssertEqual(titles, ["Record", "Transcribe Audio File...", "Settings", "Quit"])
        XCTAssertFalse(titles.contains("Dashboard..."))
        XCTAssertFalse(titles.contains("Help"))
    }

    private func visibleMenuTitles(from menu: NSMenu) -> [String] {
        menu.items
            .filter { !$0.isSeparatorItem }
            .map(\.title)
    }
}
