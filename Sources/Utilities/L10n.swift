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
        static var settings: String { isCN ? "偏好设置..." : "Settings..." }
        static var help: String { isCN ? "帮助" : "Help" }
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
        static var calendarHint: String { isCN ? "旧版只有汇总，轮次和耗时按总量估算；长记录会横向滚动" : "Legacy rows use aggregate estimates for sessions and time. Long history scrolls horizontally." }
        static var less: String { isCN ? "少" : "Less" }
        static var more: String { isCN ? "多" : "More" }
        static var dayOverview: String { isCN ? "当日概览" : "Day Overview" }
        static var transcriptionTime: String { isCN ? "转录耗时" : "Transcription Time" }
        static var transcriptionTimeFooter: String { isCN ? "最近 20 次转录的处理时间（含语义纠正）" : "Processing time for recent 20 transcriptions (incl. semantic correction)." }
        static var topSources: String { isCN ? "常用来源" : "Top Sources" }
        static var noSources: String { isCN ? "暂无来源数据" : "No sources yet." }
        static var providerMix: String { isCN ? "引擎占比" : "Provider Mix" }
        static var sourceMix: String { isCN ? "来源分布" : "Source Mix" }
        static var modelBreakdown: String { isCN ? "模型" : "Models" }
        static var dayBreakdown: String { isCN ? "当日构成" : "Day Breakdown" }
        static var noDataForDay: String { isCN ? "这一天暂无保存的转录记录" : "No saved transcripts for this day." }
        static var aggregateOnlyDay: String { isCN ? "这一天只有旧版汇总数据，没有逐条转录明细" : "Only legacy aggregate data is available for this day; individual transcripts were not saved." }
        static var legacySummary: String { isCN ? "旧版汇总" : "Legacy Summary" }
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
            isCN ? "旧记录可能只有总耗时。完成新的转录后，这里会开始显示分阶段拆分。" :
                "Older records may only have total processing time. New runs will include stage breakdowns."
        }
        static var runBreakdown: String { isCN ? "单次耗时拆分" : "Run Breakdown" }
        static var slowestStage: String { isCN ? "主要瓶颈" : "Main Bottleneck" }
        static var slowestRun: String { isCN ? "最慢单次" : "Slowest Run" }
        static var averageProcessing: String { isCN ? "平均处理" : "Avg. Processing" }
        static var analyzedRuns: String { isCN ? "分析记录" : "Runs" }
        static var stageDistribution: String { isCN ? "阶段占比" : "Stage Distribution" }
        static var recordDetails: String { isCN ? "记录明细" : "Record Details" }
        static var legacyProcessing: String { isCN ? "处理总耗时（旧记录）" : "Processing Total (Legacy)" }
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
        static var oldRecordHint: String { isCN ? "旧记录没有阶段字段" : "Legacy record without stage fields" }
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
        static var retrying: String { isCN ? "重新转录中..." : "Retrying transcription..." }
    }

    // MARK: - Providers
    enum Provider {
        static func displayName(for provider: String) -> String {
            switch provider.lowercased() {
            case "openai": return "OpenAI"
            case "gemini": return "Gemini"
            case "local": return isCN ? "本地 Whisper" : "Local Whisper"
            case "parakeet": return "Parakeet"
            case "funasr": return "FunASR"
            default: return provider.capitalized
            }
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
        static var startAtLoginDesc: String { isCN ? "登录时自动启动 AudioWhisper" : "Launch AudioWhisper when you sign in." }
        static var expressMode: String { isCN ? "快捷模式" : "Express Mode" }
        static var expressModeDesc: String { isCN ? "快捷键直接开始/停止录音" : "Hotkey immediately starts and stops recording." }
        static var autoBoost: String { isCN ? "自动增强麦克风" : "Auto-Boost Microphone" }
        static var autoBoostDesc: String { isCN ? "录音时暂时最大化麦克风输入" : "Temporarily maximize mic input while recording." }
        static var smartPaste: String { isCN ? "智能粘贴" : "Smart Paste" }
        static var smartPasteDesc: String { isCN ? "自动粘贴完成的转录文本" : "Automatically paste finished transcripts." }
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
        static var micDesc: String { isCN ? "AudioWhisper 需要麦克风权限来录制音频进行转录。" : "AudioWhisper needs microphone access to record audio for transcription." }
        static var a11yDesc: String { isCN ? "智能粘贴需要辅助功能权限才能在其他应用中输入文本。" : "Accessibility permission is required for Smart Paste to type into other apps." }
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
