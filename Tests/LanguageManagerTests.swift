import XCTest
@testable import AudioWhisper

class LanguageManagerTests: XCTestCase {

    override func tearDown() {
        // Reset to default
        UserDefaults.standard.removeObject(forKey: "appLanguage")
        super.tearDown()
    }

    // MARK: - AppLanguage

    func testAppLanguageCases() {
        XCTAssertEqual(AppLanguage.allCases.count, 2)
        XCTAssertTrue(AppLanguage.allCases.contains(.english))
        XCTAssertTrue(AppLanguage.allCases.contains(.chinese))
    }

    func testAppLanguageRawValues() {
        XCTAssertEqual(AppLanguage.english.rawValue, "en")
        XCTAssertEqual(AppLanguage.chinese.rawValue, "zh")
    }

    func testAppLanguageDisplayNames() {
        XCTAssertEqual(AppLanguage.english.displayName, "English")
        XCTAssertEqual(AppLanguage.chinese.displayName, "中文")
    }

    func testAppLanguageFromRawValue() {
        XCTAssertEqual(AppLanguage(rawValue: "en"), .english)
        XCTAssertEqual(AppLanguage(rawValue: "zh"), .chinese)
        XCTAssertNil(AppLanguage(rawValue: "fr"))
    }

    // MARK: - LanguageManager persistence

    func testLanguageManagerDefaultsToChinese() {
        let defaults = makeIsolatedDefaults()
        defaults.removeObject(forKey: "appLanguage")

        XCTAssertEqual(LanguageManager.initialLanguage(defaults: defaults), .chinese)
    }

    func testLanguageManagerUsesDefaultForInvalidStoredLanguage() {
        let defaults = makeIsolatedDefaults()
        defaults.set("fr", forKey: "appLanguage")

        XCTAssertEqual(LanguageManager.initialLanguage(defaults: defaults), .chinese)
    }

    func testLanguageManagerUsesStoredLanguage() {
        let defaults = makeIsolatedDefaults()

        defaults.set("en", forKey: "appLanguage")
        XCTAssertEqual(LanguageManager.initialLanguage(defaults: defaults), .english)

        defaults.set("zh", forKey: "appLanguage")
        XCTAssertEqual(LanguageManager.initialLanguage(defaults: defaults), .chinese)
    }

    func testLanguageManagerPersistsChoice() {
        let manager = LanguageManager.shared
        manager.current = .chinese
        XCTAssertEqual(UserDefaults.standard.string(forKey: "appLanguage"), "zh")

        manager.current = .english
        XCTAssertEqual(UserDefaults.standard.string(forKey: "appLanguage"), "en")
    }

    // MARK: - L10n bilingual strings

    func testL10nEnglishStrings() {
        LanguageManager.shared.current = .english

        XCTAssertEqual(L10n.Nav.overview, "Overview")
        XCTAssertEqual(L10n.Nav.transcripts, "Transcripts")
        XCTAssertEqual(L10n.Home.thisMonth, "This Month")
        XCTAssertEqual(L10n.Home.words, "Words")
        XCTAssertEqual(L10n.Home.activityFooter, "Words transcribed across all saved records.")
        XCTAssertEqual(L10n.Home.viewAll, "View All…")
        XCTAssertEqual(L10n.Home.noTranscripts, "No transcripts yet.")
        XCTAssertEqual(L10n.Home.streakDays(1), "1 day")
        XCTAssertEqual(L10n.Home.streakDays(5), "5 days")
        XCTAssertEqual(L10n.Menu.record, "Record")
        XCTAssertEqual(L10n.Menu.transcribeAudioFile, "Transcribe Audio File...")
        XCTAssertEqual(L10n.Menu.settings, "Settings")
        XCTAssertEqual(L10n.Menu.quit, "Quit")
        XCTAssertEqual(L10n.Categories.categoryTypes, "Category Types")
        XCTAssertEqual(L10n.Categories.name(for: "coding", fallback: ""), "Coding")
        XCTAssertEqual(L10n.Categories.promptDescription(for: "terminal", fallback: ""), "Preserves CLI, GitHub, repo, deploy, monitoring terms, flags, and paths")
        XCTAssertEqual(L10n.Recording.preparingAudio, "Preparing audio...")
        XCTAssertEqual(L10n.Preferences.language, "Language")
        XCTAssertEqual(L10n.Common.cancel, "Cancel")
        XCTAssertEqual(L10n.Common.save, "Save")
    }

    func testL10nChineseStrings() {
        LanguageManager.shared.current = .chinese

        XCTAssertEqual(L10n.Nav.overview, "总览")
        XCTAssertEqual(L10n.Nav.transcripts, "转录记录")
        XCTAssertEqual(L10n.Home.thisMonth, "本月统计")
        XCTAssertEqual(L10n.Home.words, "字数")
        XCTAssertEqual(L10n.Home.activityFooter, "全部已保存记录的转录字数")
        XCTAssertEqual(L10n.Home.viewAll, "查看全部…")
        XCTAssertEqual(L10n.Home.noTranscripts, "暂无转录记录")
        XCTAssertEqual(L10n.Home.streakDays(5), "5 天")
        XCTAssertEqual(L10n.Menu.record, "录音")
        XCTAssertEqual(L10n.Menu.transcribeAudioFile, "转录音频文件...")
        XCTAssertEqual(L10n.Menu.settings, "设置")
        XCTAssertEqual(L10n.Menu.quit, "退出")
        XCTAssertEqual(L10n.Categories.categoryTypes, "分类类型")
        XCTAssertEqual(L10n.Categories.appAssignments, "应用分配")
        XCTAssertEqual(L10n.Categories.systemBadge, "系统")
        XCTAssertEqual(L10n.Categories.name(for: "coding", fallback: ""), "编程")
        XCTAssertTrue(L10n.Categories.promptDescription(for: "terminal", fallback: "").contains("保留 CLI、GitHub"))
        XCTAssertEqual(L10n.Recording.preparingAudio, "准备音频...")
        XCTAssertEqual(L10n.Preferences.language, "语言")
        XCTAssertEqual(L10n.Common.cancel, "取消")
        XCTAssertEqual(L10n.Common.save, "保存")
    }

    func testSystemCategoryDisplayIsLocalized() {
        let coding = CategoryDefinition.defaults.first { $0.id == "coding" }!

        LanguageManager.shared.current = .english
        XCTAssertEqual(coding.localizedDisplayName, "Coding")
        XCTAssertTrue(coding.localizedPromptDescription.contains("Preserves code"))

        LanguageManager.shared.current = .chinese
        XCTAssertEqual(coding.localizedDisplayName, "编程")
        XCTAssertTrue(coding.localizedPromptDescription.contains("保留代码"))
    }

    func testL10nProviderDisplayName() {
        LanguageManager.shared.current = .english
        XCTAssertEqual(L10n.Provider.displayName(for: "openai"), "OpenAI")
        XCTAssertEqual(L10n.Provider.displayName(for: "local"), "Local Whisper")
        XCTAssertEqual(L10n.Provider.displayName(for: "funasr"), "FunASR")

        LanguageManager.shared.current = .chinese
        XCTAssertEqual(L10n.Provider.displayName(for: "local"), "本地 Whisper")
        // OpenAI and FunASR don't change
        XCTAssertEqual(L10n.Provider.displayName(for: "openai"), "OpenAI")
    }

    func testL10nFormatDuration() {
        LanguageManager.shared.current = .english
        XCTAssertEqual(L10n.Format.duration(0), "0m")
        XCTAssertEqual(L10n.Format.duration(300), "5m")
        XCTAssertEqual(L10n.Format.duration(3660), "1h 1m")

        LanguageManager.shared.current = .chinese
        XCTAssertEqual(L10n.Format.duration(0), "0 分钟")
        XCTAssertEqual(L10n.Format.duration(300), "5 分钟")
        XCTAssertEqual(L10n.Format.duration(3660), "1 小时 1 分钟")
    }

    func testL10nWeekdays() {
        LanguageManager.shared.current = .english
        XCTAssertEqual(L10n.Weekday.short.count, 7)
        XCTAssertEqual(L10n.Weekday.short.first, "S")

        LanguageManager.shared.current = .chinese
        XCTAssertEqual(L10n.Weekday.short.count, 7)
        XCTAssertEqual(L10n.Weekday.short.first, "日")
    }

    func testL10nRecordRowAccessibility() {
        LanguageManager.shared.current = .english
        let label = L10n.RecordRow.accessibilityLabel(date: "Mar 14", provider: "openai")
        XCTAssertTrue(label.contains("Mar 14"))
        XCTAssertTrue(label.contains("openai"))

        LanguageManager.shared.current = .chinese
        let labelCN = L10n.RecordRow.accessibilityLabel(date: "3月14日", provider: "openai")
        XCTAssertTrue(labelCN.contains("3月14日"))
        XCTAssertTrue(labelCN.contains("转录于"))
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "LanguageManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
