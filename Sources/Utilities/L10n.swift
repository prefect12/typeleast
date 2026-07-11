import Foundation

/// Centralized bilingual strings. Access via `L10n.xxx`.
/// All strings check `LanguageManager.shared.current` at call time.
internal enum L10n {
    private static var lang: AppLanguage { LanguageManager.shared.current }
    private static var isCN: Bool { lang == .chinese }
    static var isChinese: Bool { isCN }

    // MARK: - Dashboard Nav
    enum Nav {
        static var overview: String { isCN ? "总览" : "Overview" }
        static var timingAnalysis: String { isCN ? "耗时分析" : "Timing Analysis" }
        static var transcripts: String { isCN ? "转录记录" : "Transcripts" }
        static var categories: String { isCN ? "分类" : "Categories" }
        static var recording: String { isCN ? "录音" : "Recording" }
        static var providers: String { isCN ? "引擎" : "Providers" }
        static var preferences: String { isCN ? "偏好设置" : "Preferences" }
        static var permissions: String { isCN ? "权限" : "Permissions" }
        static var selectSection: String { isCN ? "请在侧边栏选择一个功能" : "Select a section in the sidebar" }
    }

    // MARK: - Menu
    enum Menu {
        static var record: String { isCN ? "录音" : "Record" }
        static var transcribeAudioFile: String { isCN ? "转录音频文件..." : "Transcribe Audio File..." }
        static var dashboard: String { isCN ? "仪表盘..." : "Dashboard..." }
        static var settings: String { isCN ? "设置" : "Settings" }
        static var quit: String { isCN ? "退出" : "Quit" }
        static var closeWindow: String { isCN ? "关闭窗口" : "Close Window" }
        static var audioFilePanelMessage: String {
            isCN ? "选择要转录的音频文件" : "Select an audio file to transcribe"
        }
        static var transcribePrompt: String { isCN ? "转录" : "Transcribe" }
    }

    // MARK: - Dashboard Home
    enum Home {
        static var thisMonth: String { isCN ? "本月统计" : "This Month" }
        static var statsTitle: String { isCN ? "统计" : "Stats" }
        static var statsSubtitle: String { isCN ? "全部本地使用记录的强度、效率和来源分布" : "Usage intensity, efficiency, and source breakdown across local usage." }
        static var words: String { isCN ? "字数" : "Words" }
        static var sessions: String { isCN ? "轮次" : "Sessions" }
        static var providers: String { isCN ? "引擎" : "Providers" }
        static var characters: String { isCN ? "字符" : "Characters" }
        static var recordingDuration: String { isCN ? "录音时长" : "Recording Time" }
        static var processingDuration: String { isCN ? "处理耗时" : "Processing Time" }
        static var avgProcessing: String { isCN ? "平均处理" : "Avg. Processing" }
        static var timeSaved: String { isCN ? "节省时间" : "Time Saved" }
        static var avgWPM: String { isCN ? "平均语速 (WPM)" : "Avg. WPM" }
        static var activeDays: String { isCN ? "活跃天数" : "Active Days" }
        static var avgTranscriptionTime: String { isCN ? "平均转录耗时" : "Avg. Transcription Time" }
        static var peakDay: String { isCN ? "峰值日" : "Peak Day" }
        static var bestSingleDay: String { isCN ? "单日最高转录字数" : "Highest single-day word count" }
        static var allSavedRecords: String { isCN ? "全部本地使用汇总" : "All local usage" }
        static var basedOnTypingSpeed: String { isCN ? "按 45 WPM 打字速度估算" : "Estimated at 45 WPM typing" }
        static var processingAverage: String { isCN ? "含语义纠正的平均处理时间" : "Average ASR + correction time" }
        static var recordingBased: String { isCN ? "基于录音时长" : "Based on recording duration" }
        static func activeDaysSummary(_ n: Int) -> String { isCN ? "\(n) 个活跃日" : "\(n) active day\(n == 1 ? "" : "s")" }
        static var activity: String { isCN ? "活跃度" : "Activity" }
        static var streak: String { isCN ? "连续天数" : "Streak" }
        static func streakDays(_ n: Int) -> String { isCN ? "\(n) 天" : "\(n) day\(n == 1 ? "" : "s")" }
        static var activityFooter: String { isCN ? "全部已保存记录的转录字数" : "Words transcribed across all saved records." }
        static var calendarTitle: String { isCN ? "转录活动" : "Transcription Activity" }
        static var calendarSubtitle: String { isCN ? "按天查看综合活跃度，点击日期查看完整指标" : "Daily combined activity. Click a date to inspect all metrics." }
        static var calendarHint: String { isCN ? "累计计数会补足没有逐条记录的日期；长记录会横向滚动" : "Summary counters fill days without saved transcript details. Long history scrolls horizontally." }
        static var less: String { isCN ? "少" : "Less" }
        static var more: String { isCN ? "多" : "More" }
        static var dayOverview: String { isCN ? "当日概览" : "Day Overview" }
        static var transcriptionTime: String { isCN ? "转录耗时" : "Transcription Time" }
        static var transcriptionTimeFooter: String { isCN ? "最近 20 次转录的处理时间（含语义纠正）" : "Processing time for recent 20 transcriptions (incl. semantic correction)." }
        static var topSources: String { isCN ? "常用来源" : "Top Sources" }
        static var noSources: String { isCN ? "暂无来源数据" : "No sources yet." }
        static var sourceMix: String { isCN ? "来源分布" : "Source Mix" }
        static var modelBreakdown: String { isCN ? "模型" : "Models" }
        static var noDataForDay: String { isCN ? "这一天暂无保存的转录记录" : "No saved transcripts for this day." }
        static var summaryCountersOnlyDay: String { isCN ? "这一天只有累计计数，没有逐条转录明细" : "Only summary counters are available for this day; individual transcripts were not saved." }
        static var noBreakdownData: String { isCN ? "暂无可拆分数据" : "No breakdown data yet." }
        static var trendTitle: String { isCN ? "近期趋势" : "Recent Trend" }
        static var trendSubtitle: String { isCN ? "最近 45 天的日级变化" : "Daily movement over the last 45 visible days" }
        static var noTrendData: String { isCN ? "暂无趋势数据" : "No trend data yet." }
        static var date: String { isCN ? "日期" : "Date" }
        static var recentTranscripts: String { isCN ? "最近转录" : "Recent Transcripts" }
        static var noTranscripts: String { isCN ? "暂无转录记录" : "No transcripts yet." }
        static var viewAll: String { isCN ? "查看全部…" : "View All…" }
        static func wordsSuffix(_ n: Int) -> String { isCN ? "\(n) 字" : "\(n) words" }
        static func dayContext(sessions: Int, peakPercent: Double, weekPercent: Double) -> String {
            if isCN {
                return "\(sessions) 轮次  |  \(String(format: "%.0f", peakPercent))% 峰值日  |  \(String(format: "%.1f", weekPercent))% 本周字数"
            }
            return "\(sessions) session\(sessions == 1 ? "" : "s")  |  \(String(format: "%.0f", peakPercent))% of peak day  |  \(String(format: "%.1f", weekPercent))% of week"
        }
        static var seconds: String { isCN ? "秒" : "sec" }
    }

    // MARK: - Timing Analysis
    enum Timing {
        static var title: String { isCN ? "耗时分析" : "Timing Analysis" }
        static var subtitle: String {
            isCN ? "逐条拆分转录链路，定位录音、模型准备、ASR、语义纠正和粘贴中的主要耗时。" :
                "Break down each transcription run across recording, model prep, ASR, correction, and paste."
        }
        static var includeRecording: String { isCN ? "包含录音时间" : "Include Recording Time" }
        static var recordLimit: String { isCN ? "记录范围" : "Record Range" }
        static func latestRecords(_ count: Int) -> String { isCN ? "最近 \(count) 次" : "Latest \(count)" }
        static var allRecords: String { isCN ? "全部" : "All" }
        static var noTimingData: String { isCN ? "暂无可分析的耗时数据" : "No timing data yet." }
        static var noTimingDataHint: String {
            isCN ? "部分记录可能只有总耗时。完成新的转录后，这里会开始显示分阶段拆分。" :
                "Some records may only have total processing time. New runs will include stage breakdowns."
        }
        static func aggregateOnlyTimingHint(sessions: Int, words: Int) -> String {
            if isCN {
                return "已有 \(sessions) 次 / \(words) 字的累计统计，但没有保存可分析的逐条耗时。完成新的转录后，这里会显示阶段拆分。"
            }
            return "\(sessions) sessions / \(words) words are counted in usage, but saved timing details are unavailable. New transcriptions will appear here."
        }
        static var runBreakdown: String { isCN ? "单次耗时拆分" : "Run Breakdown" }
        static var slowestStage: String { isCN ? "主要瓶颈" : "Main Bottleneck" }
        static var slowestRun: String { isCN ? "最慢单次" : "Slowest Run" }
        static var averageProcessing: String { isCN ? "平均处理" : "Avg. Processing" }
        static var analyzedRuns: String { isCN ? "分析记录" : "Runs" }
        static var stageDistribution: String { isCN ? "阶段占比" : "Stage Distribution" }
        static var recordDetails: String { isCN ? "记录明细" : "Record Details" }
        static var primaryStage: String { isCN ? "主要耗时" : "Primary Stage" }
        static var otherStages: String { isCN ? "其它阶段" : "Other Stages" }
        static var untrackedProcessing: String { isCN ? "未拆分处理" : "Untracked Processing" }
        static var modelReady: String { isCN ? "模型准备" : "Model Prep" }
        static var asr: String { isCN ? "ASR 转录" : "ASR" }
        static var correction: String { isCN ? "语义纠正" : "Correction" }
        static var clipboard: String { isCN ? "写剪贴板" : "Clipboard" }
        static var paste: String { isCN ? "粘贴/切回应用" : "Paste" }
        static var recording: String { isCN ? "录音" : "Recording" }
        static var total: String { isCN ? "总计" : "Total" }
        static var provider: String { isCN ? "引擎" : "Provider" }
        static var source: String { isCN ? "来源" : "Source" }
        static var words: String { isCN ? "字数" : "Words" }
        static var totalOnlyRecordHint: String { isCN ? "该记录只有总耗时，没有阶段字段" : "This record has total processing time only." }
    }

    // MARK: - Transcription History
    enum History {
        static var copy: String { isCN ? "复制" : "Copy" }
        static var delete: String { isCN ? "删除" : "Delete" }
        static var clearAll: String { isCN ? "全部清除" : "Clear All" }
        static var deleteTranscriptions: String { isCN ? "删除转录记录" : "Delete Transcriptions" }
        static var clearAllTranscriptionHistory: String { isCN ? "清除全部转录历史" : "Clear All Transcription History" }
        static var irreversible: String { isCN ? "此操作无法撤销。" : "This action cannot be undone." }
        static var clearAllWarning: String { isCN ? "这会永久删除所有转录记录。" : "This will permanently delete all transcriptions." }
        static var date: String { isCN ? "日期" : "Date" }
        static var provider: String { isCN ? "引擎" : "Provider" }
        static var duration: String { isCN ? "时长" : "Duration" }
        static var text: String { isCN ? "文本" : "Text" }
        static var selectTranscript: String { isCN ? "选择一条转录记录" : "Select a Transcript" }
        static var selectTranscriptHint: String { isCN ? "在上方选择一条转录，查看完整内容。" : "Choose a transcription above to view details." }
        static var noTranscriptsYet: String { isCN ? "暂无转录记录" : "No Transcripts Yet" }
        static var noSavedTranscripts: String { isCN ? "暂无保存的转录明细" : "No Saved Transcripts" }
        static var historyWillAppear: String {
            isCN ? "完成新的转录后，转录历史会显示在这里。" :
                "Your transcription history will appear here after new transcriptions."
        }
        static func aggregateOnlyHistoryHint(sessions: Int, words: Int) -> String {
            if isCN {
                return "已有 \(sessions) 次 / \(words) 字的累计统计，但此前转录没有保存文本明细。开启历史后完成的新转录会显示在这里。"
            }
            return "\(sessions) sessions / \(words) words are counted in usage, but those older transcripts were not saved as text records. New saved transcriptions will appear here."
        }
        static var noResults: String { isCN ? "没有结果" : "No Results" }
        static var noResultsHint: String { isCN ? "换一个搜索词试试。" : "Try a different search term." }
        static var error: String { isCN ? "错误" : "Error" }
        static var failedToDelete: String { isCN ? "删除记录失败" : "Failed to delete records" }
        static var failedToClear: String { isCN ? "清除记录失败" : "Failed to clear records" }
        static var model: String { isCN ? "模型" : "Model" }
    }

    // MARK: - Weekdays
    enum Weekday {
        static var short: [String] { isCN ? ["日", "一", "二", "三", "四", "五", "六"] : ["S", "M", "T", "W", "T", "F", "S"] }
    }

    // MARK: - Recording
    enum Recording {
        static var preparingAudio: String { isCN ? "准备音频..." : "Preparing audio..." }
        static var semanticCorrection: String { isCN ? "语义纠正中..." : "Semantic correction..." }
        static var transcribingFile: String { isCN ? "正在转录文件..." : "Transcribing file..." }
        static var finalizingStreaming: String { isCN ? "正在完成…" : "Finalizing…" }
        static var retrying: String { isCN ? "重新转录中..." : "Retrying transcription..." }
    }

    // MARK: - Recording Settings
    enum RecordingSettings {
        static var microphone: String { isCN ? "麦克风" : "Microphone" }
        static var noMicrophones: String {
            isCN ? "未检测到麦克风。请接入麦克风，或检查系统权限。" :
                "No microphones detected. Plug in a microphone or check system permissions."
        }
        static var inputDevice: String { isCN ? "输入设备" : "Input Device" }
        static var systemDefault: String { isCN ? "系统默认" : "System Default" }
        static var globalHotkey: String { isCN ? "全局快捷键" : "Global Hotkey" }
        static var globalHotkeyFooter: String { isCN ? "在任何位置开始或停止录音。" : "Starts and stops recording system-wide." }
        static var changeHotkey: String { isCN ? "更改…" : "Change…" }
        static var pressKeys: String { isCN ? "按下快捷键..." : "Press keys..." }
        static var pressAnotherKey: String { isCN ? "再按一个键" : "press another key" }
        static var releaseToSave: String { isCN ? "松开保存" : "release to save" }
        static var invalidHotkey: String { isCN ? "组合不可用" : "Invalid combination" }
        static var pressAndHold: String { isCN ? "按住录音" : "Press & Hold" }
        static var enablePressAndHold: String { isCN ? "启用按住录音" : "Enable Press & Hold" }
        static var pressAndHoldDesc: String { isCN ? "按住一个修饰键来控制录音。" : "Hold a modifier key to control recording." }
        static var pressAndHoldFooter: String {
            isCN ? "在其他应用中使用需要辅助功能权限。" : "Requires Accessibility permission to work in other apps."
        }
        static var hudStyle: String { isCN ? "浮窗样式" : "Floating HUD Style" }
        static var hudStyleFooter: String {
            isCN ? "控制录音和处理状态小浮窗的视觉风格。" : "Controls the visual style of the recording and processing popup."
        }
        static var hudStyleAppleGlass: String { isCN ? "Apple 玻璃" : "Apple Glass" }
        static var hudStyleSiriAura: String { isCN ? "Siri 光晕" : "Siri Aura" }
        static var hudStyleCandidateBar: String { isCN ? "输入法候选栏" : "Candidate Bar" }
        static var behavior: String { isCN ? "行为" : "Behavior" }
        static var key: String { isCN ? "按键" : "Key" }
        static var shortcutTrigger: String { isCN ? "快捷键触发方式" : "Shortcut Trigger" }
        static var shortcutTriggerDesc: String {
            isCN ? "持续模式：双击单独修饰键开始/结束；普通组合键按一次开始、再按一次结束。快速模式：按住快捷键录音，松开结束。" :
                "Continuous: double-press a modifier-only shortcut to start/stop, or press a key combo once to start and again to stop. Quick: hold the shortcut to record, release to stop."
        }
        static var holdMode: String { isCN ? "快速模式" : "Quick Mode" }
        static var toggleMode: String { isCN ? "持续模式" : "Continuous Mode" }
        static var doubleTapMode: String { toggleMode }
        static var rightCommand: String { isCN ? "右 Command (⌘)" : "Right Command (⌘)" }
        static var leftCommand: String { isCN ? "左 Command (⌘)" : "Left Command (⌘)" }
        static var rightOption: String { isCN ? "右 Option (⌥)" : "Right Option (⌥)" }
        static var leftOption: String { isCN ? "左 Option (⌥)" : "Left Option (⌥)" }
        static var rightControl: String { isCN ? "右 Control (⌃)" : "Right Control (⌃)" }
        static var leftControl: String { isCN ? "左 Control (⌃)" : "Left Control (⌃)" }
        static var globe: String { isCN ? "Globe / Fn (🌐)" : "Globe / Fn (🌐)" }
    }

    // MARK: - Providers
    enum Provider {
        static func displayName(for provider: String) -> String {
            switch provider.lowercased() {
            case "openai": return "OpenAI"
            case "openairealtime": return "OpenAI Realtime"
            case "mimo": return "MiMo"
            case "gemini": return "Gemini"
            case "local": return isCN ? "本地 Whisper" : "Local Whisper"
            case "parakeet": return "Parakeet"
            case "funasr": return "FunASR"
            default: return provider.capitalized
            }
        }

        static var audioLanguage: String { isCN ? "音频语言" : "Audio Language" }
        static var audioLanguageFooter: String {
            isCN
                ? "自动识别会保留原始语种；短录音识别错误时可手动指定语言。"
                : "Auto-detect preserves the spoken language. Choose a language when short clips are detected incorrectly."
        }
    }

    // MARK: - Categories
    enum Categories {
        static var categoryTypes: String { isCN ? "分类类型" : "Category Types" }
        static var appAssignments: String { isCN ? "应用分配" : "App Assignments" }
        static var assignmentsFooter: String {
            isCN ? "粘贴完成的转录文本时，会自动使用对应应用的分类设置。" : "Assignments are applied automatically when you paste a finished transcript."
        }
        static var noAppsRecorded: String { isCN ? "还没有记录到应用来源。" : "No apps recorded yet." }
        static var systemBadge: String { isCN ? "系统" : "System" }
        static var newCategory: String { isCN ? "新建分类…" : "New Category…" }
        static var resetToDefaults: String { isCN ? "恢复默认" : "Reset to Defaults" }
        static var resetToDefault: String { isCN ? "恢复默认" : "Reset to Default" }
        static func editCategory(_ name: String) -> String {
            isCN ? "编辑 \(name)" : "Edit \(name)"
        }

        static var newCategoryTitle: String { isCN ? "新建分类" : "New Category" }
        static var editCategoryTitle: String { isCN ? "编辑分类" : "Edit Category" }
        static var categoryNamePlaceholder: String { isCN ? "分类名称" : "Category Name" }
        static var identifierPlaceholder: String { isCN ? "标识符" : "identifier" }
        static var identity: String { isCN ? "身份信息" : "Identity" }
        static var displayName: String { isCN ? "显示名称" : "Display Name" }
        static var identifier: String { isCN ? "标识符" : "Identifier" }
        static var systemIdentifierHelp: String { isCN ? "系统分类的标识符不能修改。" : "System category identifiers can’t be changed." }
        static var appearance: String { isCN ? "外观" : "Appearance" }
        static var icon: String { isCN ? "图标（SF Symbol）" : "Icon (SF Symbol)" }
        static var color: String { isCN ? "颜色" : "Color" }
        static var correction: String { isCN ? "纠正设置" : "Correction" }
        static var description: String { isCN ? "说明" : "Description" }
        static var promptTemplate: String { isCN ? "提示词模板" : "Prompt Template" }
        static var promptTemplateHelp: String {
            isCN ? "发送给纠正模型的该分类专用指令。" : "Instructions sent to the correction model for this category."
        }
        static var deleteCategory: String { isCN ? "删除分类" : "Delete Category" }
        static var newCategoryDefaultName: String { isCN ? "新分类" : "New Category" }
        static var categoryPurposePlaceholder: String { isCN ? "描述这个分类的用途" : "Describe this category's purpose" }
        static var displayNameRequired: String { isCN ? "显示名称不能为空。" : "Display name is required." }
        static var duplicateIdentifier: String { isCN ? "已有分类使用这个标识符。" : "A category with this identifier already exists." }

        static func name(for id: String, fallback: String) -> String {
            switch id {
            case "terminal": return isCN ? "终端" : "Terminal"
            case "coding": return isCN ? "编程" : "Coding"
            case "chat": return isCN ? "聊天" : "Chat"
            case "writing": return isCN ? "写作" : "Writing"
            case "email": return isCN ? "邮件" : "Email"
            case "general": return isCN ? "通用" : "General"
            default: return fallback
            }
        }

        static func promptDescription(for id: String, fallback: String) -> String {
            switch id {
            case "terminal":
                return isCN
                    ? "保留 CLI、GitHub、repo、部署、监控术语、参数和路径"
                    : "Preserves CLI, GitHub, repo, deploy, monitoring terms, flags, and paths"
            case "coding":
                return isCN
                    ? "保留代码、GitHub、repo、PR、campaign 和监控相关词汇"
                    : "Preserves code, GitHub, repo, PR, campaign, and monitoring vocabulary"
            case "chat":
                return isCN
                    ? "轻量纠错，保留聊天语气和中英文混合技术词"
                    : "Light corrections, keeps casual tone and mixed Chinese/English tech terms"
            case "writing":
                return isCN
                    ? "更彻底的语法整理，适合正式写作。修正句子片段和同音误识别"
                    : "Thorough grammar, formal style. Fixes fragments and homophones"
            case "email":
                return isCN
                    ? "专业邮件语气，保留问候语和落款。修正常见误识别：'attach meant' → 'attachment'"
                    : "Professional tone, preserves greetings/sign-offs. Fixes: 'attach meant' → 'attachment'"
            case "general":
                return isCN
                    ? "均衡清理，根据上下文修正常见技术词误识别"
                    : "Balanced cleanup, adapts to context, fixes common tech-term misrecognitions"
            default:
                return fallback
            }
        }
    }

    // MARK: - Duration formatting
    enum Format {
        static func duration(_ interval: TimeInterval) -> String {
            guard interval > 0 else { return isCN ? "0 分钟" : "0m" }
            let totalSeconds = Int(interval)
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            if isCN {
                return hours > 0 ? "\(hours) 小时 \(minutes) 分钟" : "\(minutes) 分钟"
            } else {
                return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
            }
        }
    }

    // MARK: - Record Row
    enum RecordRow {
        static var copyToClipboard: String { isCN ? "复制到剪贴板" : "Copy to clipboard" }
        static var delete: String { isCN ? "删除" : "Delete" }
        static func accessibilityLabel(date: String, provider: String) -> String {
            isCN ? "转录于 \(date)，使用 \(provider)" : "Transcription from \(date), using \(provider)"
        }
        static var accessibilityHint: String {
            isCN ? "点击展开或收起，使用操作按钮复制或删除" : "Tap to expand or collapse. Use action buttons to copy or delete."
        }
    }

    // MARK: - Preferences
    enum Preferences {
        static var language: String { isCN ? "语言" : "Language" }
        static var languageFooter: String { isCN ? "更改界面显示语言" : "Change the display language of the interface." }
        static var general: String { isCN ? "通用" : "General" }
        static var startAtLogin: String { isCN ? "开机启动" : "Start at Login" }
        static var startAtLoginDesc: String { isCN ? "登录时自动启动 Typeleast" : "Launch Typeleast when you sign in." }
        static var recordingMode: String { isCN ? "录音模式" : "Recording Mode" }
        static var recordingModeDesc: String {
            isCN ? "持续模式：触发快捷键后持续录音，再次触发结束。快速模式：按住快捷键录音，松开结束。" :
                "Continuous: trigger the shortcut to record until you trigger it again. Quick: hold the shortcut to record, release to stop."
        }
        static var continuousMode: String { isCN ? "持续模式" : "Continuous" }
        static var quickMode: String { isCN ? "快速模式" : "Quick" }
        static var expressMode: String { recordingMode }
        static var expressModeDesc: String { recordingModeDesc }
        static var configureShortcut: String { isCN ? "设置快捷键..." : "Configure Shortcut..." }
        static var autoBoost: String { isCN ? "自动增强麦克风" : "Auto-Boost Microphone" }
        static var autoBoostDesc: String { isCN ? "录音时暂时最大化麦克风输入" : "Temporarily maximize mic input while recording." }
        static var smartPaste: String { isCN ? "智能粘贴" : "Smart Paste" }
        static var smartPasteDesc: String { isCN ? "自动粘贴完成的转录文本" : "Automatically paste finished transcripts." }
        static var streamingTranscription: String { isCN ? "流式输入" : "Streaming Input" }
        static var streamingTranscriptionDesc: String {
            isCN ? "说话时把实时文本插入当前输入框；不可用时回退到停录后粘贴。" :
                "Insert live text into the current input while speaking, and fall back to paste-after-recording when unavailable."
        }
        static var completionSound: String { isCN ? "完成提示音" : "Completion Sound" }
        static var completionSoundDesc: String { isCN ? "转录完成时播放提示音" : "Play a chime when transcription finishes." }
        static var history: String { isCN ? "历史记录" : "History" }
        static var saveHistory: String { isCN ? "保存转录历史" : "Save Transcription History" }
        static var saveHistoryDesc: String { isCN ? "将转录记录保存到本地，方便搜索和回顾" : "Store transcripts locally so you can search and review them later." }
        static var storage: String { isCN ? "存储" : "Storage" }
        static var maxModelStorage: String { isCN ? "最大模型存储" : "Max Model Storage" }
        static var about: String { isCN ? "关于" : "About" }
        static var version: String { isCN ? "版本" : "Version" }
    }

    // MARK: - Permissions
    enum Permissions {
        static var microphone: String { isCN ? "麦克风" : "Microphone" }
        static var accessibility: String { isCN ? "辅助功能" : "Accessibility" }
        static var status: String { isCN ? "状态" : "Status" }
        static var granted: String { isCN ? "已授权" : "Granted" }
        static var denied: String { isCN ? "未授权" : "Denied" }
        static var required: String { isCN ? "需要授权" : "Required" }
        static var requestAccess: String { isCN ? "请求权限" : "Request Access" }
        static var openSettings: String { isCN ? "打开设置" : "Open Settings" }
        static var refresh: String { isCN ? "刷新" : "Refresh" }
        static var micDesc: String { isCN ? "Typeleast 需要麦克风权限来录制音频进行转录。" : "Typeleast needs microphone access to record audio for transcription." }
        static var a11yDesc: String { isCN ? "智能粘贴需要辅助功能权限才能在其他应用中输入文本。" : "Accessibility permission is required for Smart Paste to type into other apps." }
    }

    // MARK: - Smart Paste Permission Alerts
    enum SmartPastePermission {
        static var requestTitle: String {
            isCN ? "智能粘贴需要辅助功能权限" : "Accessibility Permission Required for SmartPaste"
        }
        static var requestMessage: String {
            if isCN {
                return """
                Typeleast 的智能粘贴需要辅助功能权限，才能把转录文本自动粘贴到你录音前正在使用的应用中。

                智能粘贴会做什么：
                • 把转录文本粘贴回原来的应用
                • 尝试把焦点切回录音前的应用
                • 省去手动切换和按 ⌘V

                隐私说明：
                • Typeleast 只发送粘贴快捷键（⌘V）
                • 不读取、监控或访问其他应用内容
                • 不录屏、不记录键盘输入
                • 转录在你的设备上完成

                接下来：
                • 点击“授予权限”打开系统设置
                • 在“隐私与安全性 → 辅助功能”里找到 Typeleast
                • 打开开关，然后回到 Typeleast

                如果你现在不方便打开系统设置，可以点“稍后授权”，智能粘贴会保持开启；授权前转录文本仍会复制到剪贴板。
                """
            }
            return """
            Typeleast's SmartPaste feature needs Accessibility permission to automatically paste transcribed text into your applications.

            What SmartPaste does:
            • Pastes transcribed text into the app you were using before recording
            • Switches focus back to your original application
            • Provides a hands-free voice-to-text workflow

            Privacy protection:
            • Typeleast only sends paste commands (⌘V) to applications
            • It never reads, monitors, or accesses content from other applications
            • No screen recording or keylogging occurs
            • Transcription happens on your device

            What happens next:
            • Click "Grant Permission" to open System Settings
            • Find Typeleast in Privacy & Security → Accessibility
            • Toggle the switch to enable the permission
            • Return to Typeleast to use SmartPaste

            If you cannot open System Settings now, click "Authorize Later". SmartPaste stays enabled; until permission is granted, transcribed text is still copied to your clipboard.
            """
        }
        static var grantPermission: String { isCN ? "授予权限" : "Grant Permission" }
        static var continueWithout: String { isCN ? "稍后授权" : "Authorize Later" }
        static var learnMore: String { isCN ? "了解辅助功能权限" : "Learn More About Accessibility Permissions" }

        static var enabledTitle: String { isCN ? "智能粘贴已启用" : "SmartPaste Enabled!" }
        static var enabledMessage: String {
            isCN
                ? "辅助功能权限已授权。智能粘贴现在可以把转录文本自动粘贴到其他应用中。\n\n如果你之后想手动粘贴，可以随时在 Typeleast 设置里关闭智能粘贴。"
                : "Accessibility permission has been granted successfully.\n\nSmartPaste is now enabled and will automatically paste transcribed text into your applications.\n\nYou can disable SmartPaste anytime in Typeleast Settings if you prefer manual control."
        }
        static var great: String { isCN ? "好的" : "Great!" }

        static var incompleteTitle: String { isCN ? "权限设置尚未生效" : "Permission Setup Incomplete" }
        static var incompleteMessage: String {
            if isCN {
                return """
                Typeleast 还没有检测到可用的辅助功能权限。

                这通常是因为：
                • 系统设置窗口关闭前没有完成授权
                • 你已经打开开关，但 macOS 还没刷新到当前运行的 App
                • 列表里的 Typeleast 对应先前签名或先前 App bundle

                接下来可以这样处理：
                • 点“显示手动步骤”，删除列表里的 Typeleast 后重新添加 /Applications/Typeleast.app
                • 重启 Typeleast 后再试一次
                • 转录文本仍会复制到剪贴板，你也可以手动按 ⌘V 粘贴
                """
            }
            return """
            Typeleast has not detected active Accessibility permission yet.

            This might happen if:
            • System Settings was closed without making changes
            • The permission was granted but macOS has not refreshed the running app yet
            • The Typeleast entry points to an older signature or app bundle

            What to do next:
            • Click "Show Manual Instructions", remove Typeleast, and re-add /Applications/Typeleast.app
            • Restart Typeleast and try again
            • Transcribed text is still copied to your clipboard, so you can paste manually with ⌘V
            """
        }
        static var showManualInstructions: String { isCN ? "显示手动步骤" : "Show Manual Instructions" }

        static var educationTitle: String { isCN ? "为什么需要辅助功能权限" : "Understanding macOS Accessibility Permissions" }
        static var educationMessage: String {
            if isCN {
                return """
                macOS 的辅助功能权限允许自动化工具与其他应用交互。屏幕阅读器、语音控制、Keyboard Maestro、文本扩展工具也会使用同一类权限。

                Typeleast 只需要发送一次等同于按下 ⌘V 的粘贴命令，把转录文本放回你录音前所在的位置。没有这个权限时，你需要自己切回原应用并手动粘贴。

                Typeleast 不读取其他应用内容，不录屏，也不记录键盘输入。这个权限可以随时在系统设置里撤销。
                """
            }
            return """
            macOS Accessibility permissions allow assistive technologies and automation tools to interact with other applications. This is the same permission used by screen readers, voice control, Keyboard Maestro, text expanders, and similar tools.

            Typeleast only needs to send a paste command, equivalent to pressing ⌘V, so it can place transcribed text back where you were working. Without this permission, you need to switch back and paste manually.

            Typeleast does not read other app content, record your screen, or log keystrokes. You can revoke this permission anytime in System Settings.
            """
        }
        static var iUnderstand: String { isCN ? "我知道了" : "I Understand" }

        static var manualTitle: String { isCN ? "启用辅助功能权限" : "Enable Accessibility Permission" }
        static var manualMessage: String {
            if isCN {
                return """
                手动启用智能粘贴：

                1. 点击下面的“打开系统设置”
                2. 进入“隐私与安全性 → 辅助功能”
                3. 找到 Typeleast 并打开开关
                4. 如果已经打开但仍不能粘贴，先从列表里删除 Typeleast，再用“+”重新添加 /Applications/Typeleast.app
                5. 重启 Typeleast 后再试一次
                """
            }
            return """
            To enable SmartPaste manually:

            1. Click "Open System Settings" below
            2. Go to Privacy & Security → Accessibility
            3. Find Typeleast and enable it
            4. If it is already enabled but paste still fails, remove Typeleast from the list and re-add /Applications/Typeleast.app with the "+" button
            5. Restart Typeleast and try again
            """
        }
        static var openSystemSettings: String { isCN ? "打开系统设置" : "Open System Settings" }

        static var statusGranted: String {
            isCN ? "✅ 辅助功能权限已授权，智能粘贴可用" : "✅ Accessibility permission granted - SmartPaste is enabled"
        }
        static var statusRequired: String {
            isCN ? "⚠️ 智能粘贴需要辅助功能权限" : "⚠️ Accessibility permission required for SmartPaste functionality"
        }
        static var detailedConfigured: String {
            isCN ? "辅助功能权限已正确配置" : "Accessibility permission is properly configured"
        }
        static var detailedNotGranted: String {
            isCN ? "辅助功能权限尚未授权" : "Accessibility permission is not granted"
        }
        static var troubleshootingInfo: String {
            if isCN {
                return """
                启用智能粘贴：
                1. 打开“系统设置 → 隐私与安全性 → 辅助功能”
                2. 添加 Typeleast（需要时用 + 按钮选择 /Applications/Typeleast.app）
                3. 打开 Typeleast 的开关
                4. 如果仍失败，删除原有条目、重新添加并重启 Typeleast
                """
            }
            return """
            To enable SmartPaste:
            1. Open System Settings → Privacy & Security → Accessibility
            2. Add Typeleast to the list, using the + button to choose /Applications/Typeleast.app if needed
            3. Toggle the switch to enable Typeleast
            4. If it still fails, remove the old entry, re-add it, and restart Typeleast
            """
        }

        static var errorTitle: String { isCN ? "权限请求出错" : "Permission Request Error" }
        static func errorMessage(_ description: String) -> String {
            if isCN {
                return """
                请求辅助功能权限时出现错误：

                \(description)

                你仍然可以手动启用智能粘贴：
                1. 打开系统设置
                2. 进入“隐私与安全性 → 辅助功能”
                3. 添加 Typeleast 并打开开关

                授权完成前，转录文本会继续复制到剪贴板。
                """
            }
            return """
            An error occurred while requesting Accessibility permission:

            \(description)

            You can still enable SmartPaste manually:
            1. Open System Settings
            2. Go to Privacy & Security → Accessibility
            3. Add Typeleast and enable it

            Until permission is granted, transcribed text will be copied to your clipboard for manual pasting.
            """
        }

        static var disabledTitle: String { isCN ? "稍后授权智能粘贴" : "SmartPaste Authorization Later" }
        static var disabledMessage: String {
            isCN
                ? "智能粘贴会保持开启。授权完成前，Typeleast 会继续复制转录文本到剪贴板，你可以手动按 ⌘V 粘贴。"
                : "SmartPaste stays enabled. Until permission is granted, Typeleast will continue to copy transcribed text to your clipboard for manual pasting."
        }
    }

    enum PasteErrors {
        static var accessibilityPermissionDenied: String {
            isCN
                ? "智能粘贴需要辅助功能权限。请在系统设置 → 隐私与安全性 → 辅助功能中启用 Typeleast。"
                : "Accessibility permission is required for SmartPaste. Please enable it in System Settings > Privacy & Security > Accessibility."
        }
        static var eventSourceCreationFailed: String {
            isCN ? "无法创建粘贴事件源。" : "Could not create event source for paste operation."
        }
        static var keyboardEventCreationFailed: String {
            isCN ? "无法创建粘贴快捷键事件。" : "Could not create keyboard events for paste operation."
        }
        static var targetAppNotAvailable: String {
            isCN ? "目标应用不可用，无法粘贴。" : "Target application is not available for pasting."
        }
    }

    // MARK: - Common
    enum Common {
        static var cancel: String { isCN ? "取消" : "Cancel" }
        static var save: String { isCN ? "保存" : "Save" }
        static var add: String { isCN ? "添加" : "Add" }
        static var done: String { isCN ? "完成" : "Done" }
        static var reset: String { isCN ? "重置" : "Reset" }
        static var install: String { isCN ? "安装" : "Install" }
        static var installed: String { isCN ? "已安装" : "Installed" }
        static var ready: String { isCN ? "就绪" : "Ready" }
        static var setupRequired: String { isCN ? "需要配置" : "Setup required" }
        static var downloaded: String { isCN ? "已下载" : "Downloaded" }
        static var notDownloaded: String { isCN ? "未下载" : "Not downloaded" }
        static var recommended: String { isCN ? "推荐" : "RECOMMENDED" }
        static var environment: String { isCN ? "环境" : "Environment" }
        static var model: String { isCN ? "模型" : "Model" }
        static var advanced: String { isCN ? "高级" : "Advanced" }
    }
}
