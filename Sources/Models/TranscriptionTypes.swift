import Foundation

internal enum WhisperModelError: Error, LocalizedError, Sendable {
    case invalidURL(fileName: String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL(let fileName):
            return "Invalid URL for whisper model file: \(fileName)"
        }
    }
}

internal enum TranscriptionProvider: String, CaseIterable, Codable, Sendable {
    case openai = "openai"
    case mimo = "mimo"
    case gemini = "gemini" 
    case local = "local"
    case parakeet = "parakeet"
    
    var displayName: String {
        switch self {
        case .openai:
            return "OpenAI Whisper (Cloud)"
        case .mimo:
            return "Xiaomi MiMo V2.5 ASR (Cloud)"
        case .gemini:
            return "Google Gemini (Cloud)"
        case .local:
            return "Whisper (Local)"
        case .parakeet:
            return "Parakeet (Advanced)"
        }
    }
}

internal enum TranscriptionLanguage: String, CaseIterable, Codable, Sendable, Identifiable {
    case auto
    case chineseEnglish = "zh-en"
    case chinese = "zh"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case spanish = "es"
    case french = "fr"
    case german = "de"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto:
            return L10n.isChinese ? "自动识别" : "Auto-detect"
        case .chineseEnglish:
            return L10n.isChinese ? "中英混输" : "Chinese + English"
        case .chinese:
            return L10n.isChinese ? "中文" : "Chinese"
        case .english:
            return L10n.isChinese ? "英语" : "English"
        case .japanese:
            return L10n.isChinese ? "日语" : "Japanese"
        case .korean:
            return L10n.isChinese ? "韩语" : "Korean"
        case .spanish:
            return L10n.isChinese ? "西班牙语" : "Spanish"
        case .french:
            return L10n.isChinese ? "法语" : "French"
        case .german:
            return L10n.isChinese ? "德语" : "German"
        }
    }

    var apiLanguageCode: String? {
        switch self {
        case .auto, .chineseEnglish:
            return nil
        default:
            return rawValue
        }
    }

    var openAITranscriptionLanguageCode: String? {
        switch self {
        case .auto, .chinese, .chineseEnglish:
            return nil
        default:
            return rawValue
        }
    }

    var mimoASRLanguageCode: String {
        switch self {
        case .auto, .chinese, .chineseEnglish:
            return "auto"
        default:
            return rawValue
        }
    }

    var speechInstruction: String {
        switch self {
        case .auto:
            return "Detect the spoken language automatically. Preserve the original spoken language and mixed-language wording, especially English words inside Chinese speech; do not translate."
        case .chineseEnglish:
            return "The speech intentionally mixes Mandarin Chinese and English. Transcribe each word in the language spoken, preserve English words, acronyms, product names, commands, code identifiers, and technical terms exactly, and do not translate."
        case .chinese:
            return "The speech is primarily Chinese and may include English words, acronyms, product names, commands, code identifiers, and technical terms. Transcribe Chinese as Chinese, preserve spoken English exactly, and do not translate or convert English into Chinese phonetic approximations."
        case .english:
            return "The spoken language is English. Transcribe in English and do not translate."
        case .japanese:
            return "The spoken language is Japanese. Transcribe in Japanese and do not translate."
        case .korean:
            return "The spoken language is Korean. Transcribe in Korean and do not translate."
        case .spanish:
            return "The spoken language is Spanish. Transcribe in Spanish and do not translate."
        case .french:
            return "The spoken language is French. Transcribe in French and do not translate."
        case .german:
            return "The spoken language is German. Transcribe in German and do not translate."
        }
    }
}

internal enum WhisperModel: String, CaseIterable, Codable, Sendable {
    case tiny = "tiny"
    case base = "base"
    case small = "small"
    case largeTurbo = "large-v3-turbo"

    var displayName: String {
        switch self {
        case .tiny:
            return "Tiny (39MB)"
        case .base:
            return "Base (142MB)"
        case .small:
            return "Small (466MB)"
        case .largeTurbo:
            return "Large Turbo (1.5GB)"
        }
    }

    var fileSize: String {
        switch self {
        case .tiny:
            return "39MB"
        case .base:
            return "142MB"
        case .small:
            return "466MB"
        case .largeTurbo:
            return "1.5GB"
        }
    }

    var fileName: String {
        return "ggml-\(rawValue).bin"
    }

    var downloadURL: URL {
        // Safe fallback version - returns base model URL if current model URL is invalid
        do {
            return try getDownloadURL()
        } catch {
            // Fallback to base model if there's an issue with the current model URL
            return URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin")!
        }
    }

    func getDownloadURL() throws -> URL {
        guard let url = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)") else {
            throw WhisperModelError.invalidURL(fileName: fileName)
        }
        return url
    }

    var description: String {
        switch self {
        case .tiny:
            return "Fastest, basic accuracy"
        case .base:
            return "Good balance of speed and accuracy"
        case .small:
            return "Better accuracy, reasonable speed"
        case .largeTurbo:
            return "Highest accuracy, optimized for speed"
        }
    }
}

internal enum ParakeetModel: String, CaseIterable, Codable, Sendable {
    case v2English = "mlx-community/parakeet-tdt-0.6b-v2"
    case v3Multilingual = "mlx-community/parakeet-tdt-0.6b-v3"

    var displayName: String {
        switch self {
        case .v2English:
            return "v2 English (~2.5 GB)"
        case .v3Multilingual:
            return "v3 Multilingual (~2.5 GB)"
        }
    }

    var description: String {
        switch self {
        case .v2English:
            return "English only, original model"
        case .v3Multilingual:
            return "25 languages, auto-detection"
        }
    }

    var repoId: String {
        rawValue
    }
}
