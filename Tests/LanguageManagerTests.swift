import XCTest
@testable import Typeleast

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
        let defaults = makeIsolatedDefaults()
        let manager = LanguageManager(defaults: defaults)
        manager.current = .chinese
        XCTAssertEqual(defaults.string(forKey: "appLanguage"), "zh")

        manager.current = .english
        XCTAssertEqual(defaults.string(forKey: "appLanguage"), "en")
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
        XCTAssertEqual(L10n.Menu.dashboard, "Dashboard...")
        XCTAssertEqual(L10n.Menu.settings, "Settings")
        XCTAssertEqual(L10n.Menu.quit, "Quit")
        XCTAssertEqual(L10n.Categories.categoryTypes, "Category Types")
        XCTAssertEqual(L10n.Categories.name(for: "coding", fallback: ""), "Coding")
        XCTAssertEqual(L10n.Categories.promptDescription(for: "terminal", fallback: ""), "Preserves CLI, GitHub, repo, deploy, monitoring terms, flags, and paths")
        XCTAssertEqual(L10n.Recording.preparingAudio, "Preparing audio...")
        XCTAssertEqual(L10n.RecordingSettings.globalHotkey, "Global Hotkey")
        XCTAssertEqual(L10n.RecordingSettings.changeHotkey, "Change…")
        XCTAssertEqual(L10n.RecordingSettings.pressAnotherKey, "press another key")
        XCTAssertEqual(L10n.RecordingSettings.releaseToSave, "release to save")
        XCTAssertEqual(L10n.RecordingSettings.holdMode, "Quick Mode")
        XCTAssertEqual(L10n.RecordingSettings.doubleTapMode, "Continuous Mode")
        XCTAssertEqual(L10n.RecordingSettings.shortcutTrigger, "Shortcut Trigger")
        XCTAssertEqual(L10n.RecordingSettings.rightCommand, "Right Command (⌘)")
        XCTAssertEqual(L10n.Preferences.language, "Language")
        XCTAssertEqual(L10n.Preferences.recordingMode, "Recording Mode")
        XCTAssertEqual(L10n.Preferences.continuousMode, "Continuous")
        XCTAssertEqual(L10n.Preferences.quickMode, "Quick")
        XCTAssertEqual(L10n.Preferences.configureShortcut, "Configure Shortcut...")
        XCTAssertEqual(L10n.SmartPastePermission.requestTitle, "Accessibility Permission Required for SmartPaste")
        XCTAssertEqual(L10n.PasteErrors.accessibilityPermissionDenied, "Accessibility permission is required for SmartPaste. Please enable it in System Settings > Privacy & Security > Accessibility.")
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
        XCTAssertEqual(L10n.Menu.dashboard, "仪表盘...")
        XCTAssertEqual(L10n.Menu.settings, "设置")
        XCTAssertEqual(L10n.Menu.quit, "退出")
        XCTAssertEqual(L10n.Categories.categoryTypes, "分类类型")
        XCTAssertEqual(L10n.Categories.appAssignments, "应用分配")
        XCTAssertEqual(L10n.Categories.systemBadge, "系统")
        XCTAssertEqual(L10n.Categories.name(for: "coding", fallback: ""), "编程")
        XCTAssertTrue(L10n.Categories.promptDescription(for: "terminal", fallback: "").contains("保留 CLI、GitHub"))
        XCTAssertEqual(L10n.Recording.preparingAudio, "准备音频...")
        XCTAssertEqual(L10n.RecordingSettings.globalHotkey, "全局快捷键")
        XCTAssertEqual(L10n.RecordingSettings.changeHotkey, "更改…")
        XCTAssertEqual(L10n.RecordingSettings.expressMode, "快捷模式")
        XCTAssertEqual(L10n.RecordingSettings.recordingExperience, "录音体验")
        XCTAssertEqual(L10n.RecordingSettings.livePreview, "实时转写预览")
        XCTAssertEqual(L10n.RecordingSettings.pressAnotherKey, "再按一个键")
        XCTAssertEqual(L10n.RecordingSettings.releaseToSave, "松开保存")
        XCTAssertEqual(L10n.RecordingSettings.holdMode, "快速模式")
        XCTAssertEqual(L10n.RecordingSettings.doubleTapMode, "持续模式")
        XCTAssertEqual(L10n.RecordingSettings.shortcutTrigger, "快捷键触发方式")
        XCTAssertEqual(L10n.RecordingSettings.rightCommand, "右 Command (⌘)")
        XCTAssertEqual(L10n.Preferences.language, "语言")
        XCTAssertEqual(L10n.Preferences.recordingMode, "录音模式")
        XCTAssertEqual(L10n.Preferences.continuousMode, "持续模式")
        XCTAssertEqual(L10n.Preferences.quickMode, "快速模式")
        XCTAssertEqual(L10n.Preferences.configureShortcut, "设置快捷键...")
        XCTAssertEqual(L10n.SmartPastePermission.requestTitle, "智能粘贴需要辅助功能权限")
        XCTAssertEqual(L10n.PasteErrors.accessibilityPermissionDenied, "智能粘贴需要辅助功能权限。请在系统设置 → 隐私与安全性 → 辅助功能中启用 Typeleast。")
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
        XCTAssertEqual(L10n.Provider.displayName(for: "openaiRealtime"), "OpenAI Realtime")
        XCTAssertEqual(L10n.Provider.displayName(for: "mimo"), "MiMo")
        XCTAssertEqual(L10n.Provider.displayName(for: "local"), "Local Whisper")
        XCTAssertEqual(L10n.Provider.displayName(for: "funasr"), "FunASR")
        XCTAssertEqual(L10n.Provider.audioLanguage, "Audio Language")

        LanguageManager.shared.current = .chinese
        XCTAssertEqual(L10n.Provider.displayName(for: "local"), "本地 Whisper")
        // OpenAI and FunASR don't change
        XCTAssertEqual(L10n.Provider.displayName(for: "openai"), "OpenAI")
        XCTAssertEqual(L10n.Provider.displayName(for: "openaiRealtime"), "OpenAI 实时")
        XCTAssertEqual(L10n.Provider.displayName(for: "mimo"), "MiMo")
        XCTAssertEqual(L10n.Provider.audioLanguage, "音频语言")
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
