import Foundation
import Alamofire
import os.log
import Observation

internal enum SpeechToTextError: Error, LocalizedError {
    case invalidURL
    case apiKeyMissing(String)
    case transcriptionFailed(String)
    case localTranscriptionFailed(Error)
    case fileTooLarge
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return LocalizedStrings.Errors.invalidAudioFile
        case .apiKeyMissing(let provider):
            return LocalizedStrings.Errors.apiKeyMissing
                .replacingOccurrences(of: "%@", with: provider)
        case .transcriptionFailed(let message):
            return LocalizedStrings.Errors.transcriptionFailed
                .replacingOccurrences(of: "%@", with: message)
        case .localTranscriptionFailed(let error):
            return LocalizedStrings.Errors.localTranscriptionFailed
                .replacingOccurrences(of: "%@", with: error.localizedDescription)
        case .fileTooLarge:
            return LocalizedStrings.Errors.fileTooLarge
        }
    }
}

@Observable
internal class SpeechToTextService {
    private let localWhisperService: LocalWhisperService
    private let parakeetService: ParakeetService
    private let keychainService: KeychainServiceProtocol
    private let userDefaults: UserDefaults
    private let correctionService = SemanticCorrectionService()

    internal static func technicalASRPrompt(language: TranscriptionLanguage = .auto) -> String {
        """
        \(language.speechInstruction)
        Preserve and correctly spell GitHub, repo, repository, PR, pull request, branch, commit, merge, rebase, issue, release, deploy, rollback, campaign, CampaignStrategy, Arachne, creator, matching, pipeline, queue, worker, webhook, monitoring, monitor, alert, alarm, metric, metrics, dashboard, log, logs, trace, tracing, span, latency, timeout, QPS, RPS, p95, p99, SLA, SLO, Sentry, Grafana, Prometheus, OpenTelemetry, OTel, Datadog, Guance, Feishu, WeChat, Claude, Codex, ChatGPT.
        Common speech variants: 进 Hub, 金 Hub, or Git Hub usually means GitHub; 瑞坡 usually means repo; 批啊 or P R usually means PR; 康佩恩 usually means campaign; 格拉法纳 means Grafana; 普罗米修斯 means Prometheus; 观测云 means Guance.
        Return only the transcription without commentary.
        """
    }

    internal static func geminiTranscriptionPrompt(language: TranscriptionLanguage = .auto) -> String {
        """
        Transcribe this audio to text. Return only the transcription without any additional text.

        \(technicalASRPrompt(language: language))
        """
    }
    
    init(
        localWhisperService: LocalWhisperService = .shared,
        parakeetService: ParakeetService = ParakeetService(),
        keychainService: KeychainServiceProtocol = KeychainService.shared,
        userDefaults: UserDefaults = .standard
    ) {
        self.localWhisperService = localWhisperService
        self.parakeetService = parakeetService
        self.keychainService = keychainService
        self.userDefaults = userDefaults
    }
    
    // Raw transcription without semantic correction
    func transcribeRaw(audioURL: URL, provider: TranscriptionProvider, model: WhisperModel? = nil) async throws -> String {
        // Validate audio file before processing
        let validationResult = await AudioValidator.validateAudioFile(at: audioURL)
        switch validationResult {
        case .valid(_): break
        case .invalid(let error):
            throw SpeechToTextError.transcriptionFailed(error.localizedDescription)
        }
        switch provider {
        case .openai:
            return try await transcribeWithOpenAI(audioURL: audioURL)
        case .mimo:
            return try await transcribeWithMiMo(audioURL: audioURL)
        case .gemini:
            return try await transcribeWithGemini(audioURL: audioURL)
        case .local:
            guard let model = model else {
                throw SpeechToTextError.transcriptionFailed("Whisper model required for local transcription")
            }
            return try await transcribeWithLocal(audioURL: audioURL, model: model)
        case .parakeet:
            return try await transcribeWithParakeet(audioURL: audioURL)
        }
    }

    func transcribe(audioURL: URL) async throws -> String {
        let useOpenAI = userDefaults.bool(forKey: "useOpenAI")
        if useOpenAI != false { // Default to OpenAI if not set
            let text = try await transcribeWithOpenAI(audioURL: audioURL)
            return await correctionService.correct(text: text, providerUsed: .openai)
        } else {
            let text = try await transcribeWithGemini(audioURL: audioURL)
            return await correctionService.correct(text: text, providerUsed: .gemini)
        }
    }
    
    func transcribe(audioURL: URL, provider: TranscriptionProvider, model: WhisperModel? = nil) async throws -> String {
        // Validate audio file before processing
        let validationResult = await AudioValidator.validateAudioFile(at: audioURL)
        switch validationResult {
        case .valid(_):
            break // Audio file validated successfully
        case .invalid(let error):
            throw SpeechToTextError.transcriptionFailed(error.localizedDescription)
        }
        
        switch provider {
        case .openai:
            let text = try await transcribeWithOpenAI(audioURL: audioURL)
            return await correctionService.correct(text: text, providerUsed: .openai)
        case .mimo:
            let text = try await transcribeWithMiMo(audioURL: audioURL)
            return await correctionService.correct(text: text, providerUsed: .mimo)
        case .gemini:
            let text = try await transcribeWithGemini(audioURL: audioURL)
            return await correctionService.correct(text: text, providerUsed: .gemini)
        case .local:
            guard let model = model else {
                throw SpeechToTextError.transcriptionFailed("Whisper model required for local transcription")
            }
            let text = try await transcribeWithLocal(audioURL: audioURL, model: model)
            return await correctionService.correct(text: text, providerUsed: .local)
        case .parakeet:
            let text = try await transcribeWithParakeet(audioURL: audioURL)
            return await correctionService.correct(text: text, providerUsed: .parakeet)
        }
    }
    
    private var geminiBaseURL: String {
        let custom = userDefaults.string(forKey: "geminiBaseURL") ?? ""
        if custom.isEmpty {
            return "https://generativelanguage.googleapis.com"
        }
        // Remove trailing slash if present
        return custom.hasSuffix("/") ? String(custom.dropLast()) : custom
    }

    /// Returns the full transcription endpoint URL for OpenAI-compatible APIs.
    /// If the custom URL contains "audio/transcriptions", it's treated as a full endpoint.
    /// Otherwise, "/audio/transcriptions" is appended to the base URL.
    private var openAITranscriptionEndpoint: String {
        let custom = userDefaults.string(forKey: "openAIBaseURL") ?? ""
        if custom.isEmpty {
            return "https://api.openai.com/v1/audio/transcriptions"
        }
        // If the URL already contains the transcriptions path, use it directly
        // This supports Azure: https://foo.openai.azure.com/openai/deployments/whisper/audio/transcriptions?api-version=2024-02-01
        if custom.contains("audio/transcriptions") {
            return custom
        }
        // Otherwise treat as base URL and append the path
        let base = custom.hasSuffix("/") ? String(custom.dropLast()) : custom
        return "\(base)/audio/transcriptions"
    }

    /// Returns the MiMo chat-completions endpoint used by the V2.5 ASR OpenAI-compatible API.
    /// If the custom URL contains "chat/completions", it's treated as a full endpoint.
    /// Otherwise, "/chat/completions" is appended to the base URL.
    private var miMoChatCompletionEndpoint: String {
        let custom = userDefaults.string(forKey: "miMoBaseURL") ?? ""
        if custom.isEmpty {
            return "https://api.xiaomimimo.com/v1/chat/completions"
        }
        if custom.contains("chat/completions") {
            return custom
        }
        let base = custom.hasSuffix("/") ? String(custom.dropLast()) : custom
        return "\(base)/chat/completions"
    }

    var resolvedOpenAITranscriptionModel: String {
        let configured = userDefaults
            .string(forKey: AppDefaults.Keys.openAITranscriptionModel)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let configured, !configured.isEmpty else {
            return AppDefaults.defaultOpenAITranscriptionModel
        }
        return configured
    }

    var resolvedMiMoASRModel: String {
        let configured = userDefaults
            .string(forKey: AppDefaults.Keys.miMoASRModel)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let configured, !configured.isEmpty else {
            return AppDefaults.defaultMiMoASRModel
        }
        return configured
    }

    var resolvedTranscriptionLanguage: TranscriptionLanguage {
        let raw = userDefaults.string(forKey: AppDefaults.Keys.transcriptionLanguage) ?? AppDefaults.defaultTranscriptionLanguage.rawValue
        return TranscriptionLanguage(rawValue: raw) ?? AppDefaults.defaultTranscriptionLanguage
    }

    /// Detects if the endpoint is Azure OpenAI based on the URL pattern
    private var isAzureOpenAI: Bool {
        let custom = userDefaults.string(forKey: "openAIBaseURL") ?? ""
        return custom.contains(".openai.azure.com")
    }

    private func transcribeWithOpenAI(audioURL: URL) async throws -> String {
        // Get API key from keychain
        guard let apiKey = keychainService.getQuietly(service: AppIdentity.keychainService, account: "OpenAI") else {
            throw SpeechToTextError.apiKeyMissing("OpenAI")
        }

        // Azure uses "api-key" header, OpenAI uses "Authorization: Bearer"
        let headers: HTTPHeaders
        if isAzureOpenAI {
            headers = ["api-key": apiKey]
        } else {
            headers = ["Authorization": "Bearer \(apiKey)"]
        }

        let transcriptionURL = openAITranscriptionEndpoint
        let language = resolvedTranscriptionLanguage
        guard let modelData = resolvedOpenAITranscriptionModel.data(using: .utf8),
              let promptData = Self.technicalASRPrompt(language: language).data(using: .utf8) else {
            throw SpeechToTextError.transcriptionFailed("Failed to encode OpenAI transcription request")
        }

        return try await withCheckedThrowingContinuation { continuation in
            AF.upload(
                multipartFormData: { multipartFormData in
                    multipartFormData.append(audioURL, withName: "file")
                    // Azure deployments already specify the model, but OpenAI-compatible APIs still expect the field.
                    multipartFormData.append(modelData, withName: "model")
                    multipartFormData.append(promptData, withName: "prompt")
                    if let languageCode = language.apiLanguageCode,
                       let languageData = languageCode.data(using: .utf8) {
                        multipartFormData.append(languageData, withName: "language")
                    }
                },
                to: transcriptionURL,
                headers: headers
            )
            .responseDecodable(of: WhisperResponse.self) { response in
                switch response.result {
                case .success(let whisperResponse):
                    let cleanedText = Self.cleanTranscriptionText(whisperResponse.text)
                    continuation.resume(returning: cleanedText)
                case .failure(let error):
                    continuation.resume(throwing: SpeechToTextError.transcriptionFailed(error.localizedDescription))
                }
            }
        }
    }

    private func transcribeWithMiMo(audioURL: URL) async throws -> String {
        guard let apiKey = keychainService.getQuietly(service: AppIdentity.keychainService, account: "MiMo") else {
            throw SpeechToTextError.apiKeyMissing("MiMo")
        }

        let fileAttributes = try FileManager.default.attributesOfItem(atPath: audioURL.path)
        let fileSize = fileAttributes[.size] as? Int64 ?? 0
        if fileSize > 25 * 1024 * 1024 {
            throw SpeechToTextError.fileTooLarge
        }

        let audioData = try Data(contentsOf: audioURL)
        let dataURI = Self.miMoAudioDataURI(
            data: audioData,
            mimeType: Self.mimeType(forAudioURL: audioURL)
        )
        let body = MiMoChatCompletionRequest.make(
            model: resolvedMiMoASRModel,
            dataURI: dataURI,
            language: resolvedTranscriptionLanguage
        )
        let headers: HTTPHeaders = [
            "api-key": apiKey,
            "Content-Type": "application/json"
        ]

        return try await withCheckedThrowingContinuation { continuation in
            AF.request(
                miMoChatCompletionEndpoint,
                method: .post,
                parameters: body,
                encoder: JSONParameterEncoder.default,
                headers: headers
            )
            .responseDecodable(of: MiMoChatCompletionResponse.self) { response in
                switch response.result {
                case .success(let miMoResponse):
                    if let text = miMoResponse.choices.first?.message.content {
                        continuation.resume(returning: Self.cleanTranscriptionText(text))
                    } else {
                        continuation.resume(throwing: SpeechToTextError.transcriptionFailed("No text in response"))
                    }
                case .failure(let error):
                    continuation.resume(throwing: SpeechToTextError.transcriptionFailed(error.localizedDescription))
                }
            }
        }
    }
    
    private func transcribeWithGemini(audioURL: URL) async throws -> String {
        // Get API key from keychain
        guard let apiKey = keychainService.getQuietly(service: AppIdentity.keychainService, account: "Gemini") else {
            throw SpeechToTextError.apiKeyMissing("Gemini")
        }
        
        // Check file size to decide on upload method
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: audioURL.path)
        let fileSize = fileAttributes[.size] as? Int64 ?? 0
        
        // Use Files API for larger files (>10MB) to avoid memory issues
        if fileSize > 10 * 1024 * 1024 {
            return try await transcribeWithGeminiFilesAPI(audioURL: audioURL, apiKey: apiKey, language: resolvedTranscriptionLanguage)
        } else {
            return try await transcribeWithGeminiInline(audioURL: audioURL, apiKey: apiKey, language: resolvedTranscriptionLanguage)
        }
    }
    
    private func transcribeWithGeminiFilesAPI(audioURL: URL, apiKey: String, language: TranscriptionLanguage) async throws -> String {
        // First, upload the file using Files API
        let fileUploadURL = "\(geminiBaseURL)/upload/v1beta/files"
        
        let uploadHeaders: HTTPHeaders = [
            "X-Goog-Api-Key": apiKey
        ]
        
        // Upload file using multipart form data
        let uploadedFile = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GeminiFileResponse, Error>) in
            AF.upload(
                multipartFormData: { multipartFormData in
                    multipartFormData.append(audioURL, withName: "file")
                    let metadata = ["file": ["display_name": "audio_recording"]]
                    if let metadataData = try? JSONSerialization.data(withJSONObject: metadata) {
                        multipartFormData.append(metadataData, withName: "metadata", mimeType: "application/json")
                    }
                },
                to: fileUploadURL,
                headers: uploadHeaders
            )
            .responseDecodable(of: GeminiFileResponse.self) { response in
                switch response.result {
                case .success(let fileResponse):
                    continuation.resume(returning: fileResponse)
                case .failure(let error):
                    continuation.resume(throwing: SpeechToTextError.transcriptionFailed("File upload failed: \(error.localizedDescription)"))
                }
            }
        }
        
        // Now use the uploaded file for transcription
        let transcriptionURL = "\(geminiBaseURL)/v1beta/models/gemini-2.5-flash-lite:generateContent"
        
        let headers: HTTPHeaders = [
            "X-Goog-Api-Key": apiKey,
            "Content-Type": "application/json"
        ]
        
        let body: [String: Any] = [
            "contents": [[
                "parts": [[
                    "file_data": [
                        "mime_type": "audio/mp4",
                        "file_uri": uploadedFile.file.uri
                    ]
                ], [
                    "text": Self.geminiTranscriptionPrompt(language: language)
                ]]
            ]]
        ]
        
        return try await withCheckedThrowingContinuation { continuation in
            AF.request(transcriptionURL, method: .post, parameters: body, encoding: JSONEncoding.default, headers: headers)
                .responseDecodable(of: GeminiResponse.self) { response in
                    switch response.result {
                    case .success(let geminiResponse):
                        if let text = geminiResponse.candidates.first?.content.parts.first?.text {
                            let cleanedText = Self.cleanTranscriptionText(text)
                            continuation.resume(returning: cleanedText)
                        } else {
                            continuation.resume(throwing: SpeechToTextError.transcriptionFailed("No text in response"))
                        }
                    case .failure(let error):
                        continuation.resume(throwing: SpeechToTextError.transcriptionFailed(error.localizedDescription))
                    }
                }
        }
    }
    
    private func transcribeWithGeminiInline(audioURL: URL, apiKey: String, language: TranscriptionLanguage) async throws -> String {
        // For smaller files, use inline data to avoid the extra upload step
        // Double-check file size for safety
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: audioURL.path)
        let fileSize = fileAttributes[.size] as? Int64 ?? 0
        
        // Enforce stricter memory limit for inline processing
        if fileSize > 5 * 1024 * 1024 { // 5MB limit
            throw SpeechToTextError.fileTooLarge
        }
        
        let audioData = try Data(contentsOf: audioURL)
        
        // Use autoreleasepool to manage memory pressure
        let base64Audio = autoreleasepool {
            return audioData.base64EncodedString()
        }
        
        let url = "\(geminiBaseURL)/v1beta/models/gemini-2.5-flash-lite:generateContent"
        
        let headers: HTTPHeaders = [
            "X-Goog-Api-Key": apiKey,
            "Content-Type": "application/json"
        ]
        
        let body: [String: Any] = [
            "contents": [[
                "parts": [[
                    "inline_data": [
                        "mime_type": "audio/mp4",
                        "data": base64Audio
                    ]
                ], [
                    "text": Self.geminiTranscriptionPrompt(language: language)
                ]]
            ]]
        ]
        
        return try await withCheckedThrowingContinuation { continuation in
            AF.request(url, method: .post, parameters: body, encoding: JSONEncoding.default, headers: headers)
                .responseDecodable(of: GeminiResponse.self) { response in
                    switch response.result {
                    case .success(let geminiResponse):
                        if let text = geminiResponse.candidates.first?.content.parts.first?.text {
                            let cleanedText = Self.cleanTranscriptionText(text)
                            continuation.resume(returning: cleanedText)
                        } else {
                            continuation.resume(throwing: SpeechToTextError.transcriptionFailed("No text in response"))
                        }
                    case .failure(let error):
                        continuation.resume(throwing: SpeechToTextError.transcriptionFailed(error.localizedDescription))
                    }
                }
        }
    }
    
    private func transcribeWithLocal(audioURL: URL, model: WhisperModel) async throws -> String {
        do {
            let text = try await localWhisperService.transcribe(audioFileURL: audioURL, model: model, language: resolvedTranscriptionLanguage) { progress in
                NotificationCenter.default.post(name: .transcriptionProgress, object: progress)
            }
            return Self.cleanTranscriptionText(text)
        } catch {
            throw SpeechToTextError.localTranscriptionFailed(error)
        }
    }
    
    private func transcribeWithParakeet(audioURL: URL) async throws -> String {
        guard Arch.isAppleSilicon else {
            throw SpeechToTextError.transcriptionFailed("Parakeet requires an Apple Silicon Mac.")
        }
        let modeRaw = userDefaults.string(forKey: "semanticCorrectionMode") ?? SemanticCorrectionMode.off.rawValue
        let semanticCorrectionMode = SemanticCorrectionMode(rawValue: modeRaw) ?? .off
        let shouldWarmup = semanticCorrectionMode != .off
        // Ensure managed Python environment with uv
        let pyURL = try UvBootstrap.ensureVenv(userPython: nil)
        let pythonPath = pyURL.path
        do {
            if shouldWarmup {
                let modelRepo = userDefaults.string(forKey: AppDefaults.Keys.semanticCorrectionModelRepo) ?? AppDefaults.defaultSemanticCorrectionModelRepo
                async let warmupTask: Void = MLDaemonManager.shared.warmup(type: "mlx", repo: modelRepo)
                async let transcription = parakeetService.transcribe(audioFileURL: audioURL, pythonPath: pythonPath)
                let (text, _) = try await (transcription, warmupTask)
                return Self.cleanTranscriptionText(text)
            } else {
                let text = try await parakeetService.transcribe(audioFileURL: audioURL, pythonPath: pythonPath)
                return Self.cleanTranscriptionText(text)
            }
        } catch {
            // Pass through model-not-ready distinctly so UI can redirect to Settings
            if let pe = error as? ParakeetError, pe == .modelNotReady {
                throw pe
            }
            throw SpeechToTextError.transcriptionFailed("Parakeet error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Text Cleaning
    
    /// Cleans transcription text by removing common markers and artifacts
    static func cleanTranscriptionText(_ text: String) -> String {
        var cleanedText = text
        
        // Remove bracketed markers iteratively to handle nested cases
        var previousLength = 0
        while cleanedText.count != previousLength {
            previousLength = cleanedText.count
            cleanedText = cleanedText.replacingOccurrences(
                of: "\\[[^\\[\\]]*\\]",
                with: "",
                options: .regularExpression
            )
        }
        
        // Remove parenthetical markers iteratively to handle nested cases
        previousLength = 0
        while cleanedText.count != previousLength {
            previousLength = cleanedText.count
            cleanedText = cleanedText.replacingOccurrences(
                of: "\\([^\\(\\)]*\\)",
                with: "",
                options: .regularExpression
            )
        }
        
        // Clean up whitespace
        cleanedText = cleanedText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        return normalizeTechnicalTerms(cleanedText)
    }

    static func miMoAudioDataURI(data: Data, mimeType: String) -> String {
        "data:\(mimeType);base64,\(data.base64EncodedString())"
    }

    static func mimeType(forAudioURL audioURL: URL) -> String {
        switch audioURL.pathExtension.lowercased() {
        case "m4a", "mp4":
            return "audio/mp4"
        case "mp3":
            return "audio/mpeg"
        case "wav":
            return "audio/wav"
        case "aac":
            return "audio/aac"
        case "caf":
            return "audio/x-caf"
        case "flac":
            return "audio/flac"
        case "ogg", "oga":
            return "audio/ogg"
        default:
            return "audio/mp4"
        }
    }

    private static func normalizeTechnicalTerms(_ text: String) -> String {
        var normalizedText = text
        let replacements: [(pattern: String, replacement: String)] = [
            ("\\bgithub\\b", "GitHub"),
            ("\\bgit\\s+hub\\b", "GitHub"),
            ("进\\s*hub", "GitHub"),
            ("金\\s*hub", "GitHub"),
            ("\\bopen\\s+ai\\b", "OpenAI"),
            ("\\bopenai\\b", "OpenAI"),
            ("\\bchat\\s+gpt\\b", "ChatGPT"),
            ("\\bchatgpt\\b", "ChatGPT"),
            ("\\bp\\s+r\\b", "PR")
        ]

        for replacement in replacements {
            normalizedText = normalizedText.replacingOccurrences(
                of: replacement.pattern,
                with: replacement.replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }

        return normalizedText
    }
    
}

// Response models
internal struct WhisperResponse: Codable {
    let text: String
}

internal struct GeminiResponse: Codable {
    let candidates: [GeminiCandidate]
}

internal struct GeminiCandidate: Codable {
    let content: GeminiContent
}

internal struct GeminiContent: Codable {
    let parts: [GeminiPart]
}

internal struct GeminiPart: Codable {
    let text: String?
}

internal struct GeminiFileResponse: Codable {
    let file: GeminiFile
}

internal struct GeminiFile: Codable {
    let uri: String
    let name: String
}

internal struct MiMoChatCompletionRequest: Codable, Equatable {
    let model: String
    let messages: [MiMoMessage]
    let asrOptions: MiMoASROptions

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case asrOptions = "asr_options"
    }

    static func make(model: String, dataURI: String, language: TranscriptionLanguage) -> MiMoChatCompletionRequest {
        MiMoChatCompletionRequest(
            model: model,
            messages: [
                MiMoMessage(
                    role: "user",
                    content: [
                        MiMoContent(
                            type: "input_audio",
                            inputAudio: MiMoInputAudio(data: dataURI)
                        )
                    ]
                )
            ],
            asrOptions: MiMoASROptions(language: language.mimoASRLanguageCode)
        )
    }
}

internal struct MiMoMessage: Codable, Equatable {
    let role: String
    let content: [MiMoContent]
}

internal struct MiMoContent: Codable, Equatable {
    let type: String
    let inputAudio: MiMoInputAudio

    enum CodingKeys: String, CodingKey {
        case type
        case inputAudio = "input_audio"
    }
}

internal struct MiMoInputAudio: Codable, Equatable {
    let data: String
}

internal struct MiMoASROptions: Codable, Equatable {
    let language: String
}

internal struct MiMoChatCompletionResponse: Codable {
    let choices: [Choice]

    struct Choice: Codable {
        let message: Message
    }

    struct Message: Codable {
        let content: String
    }
}
