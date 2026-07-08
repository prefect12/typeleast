import Foundation

internal struct TranscriptionProviderRequest {
    let audioURL: URL
    let whisperModel: WhisperModel?
}

internal protocol TranscriptionProviderClient: Sendable {
    var provider: TranscriptionProvider { get }
    func transcribe(_ request: TranscriptionProviderRequest) async throws -> String
}

internal protocol RawTranscriptionServicing: AnyObject {
    func transcribeRaw(audioURL: URL, provider: TranscriptionProvider, model: WhisperModel?) async throws -> String
}

extension SpeechToTextService: RawTranscriptionServicing {}

internal struct TranscriptionProviderClientRegistry {
    private let clientsByProvider: [TranscriptionProvider: any TranscriptionProviderClient]

    init(clients: [any TranscriptionProviderClient]) {
        self.clientsByProvider = Dictionary(uniqueKeysWithValues: clients.map { ($0.provider, $0) })
    }

    func client(for provider: TranscriptionProvider) throws -> any TranscriptionProviderClient {
        guard let client = clientsByProvider[provider] else {
            throw SpeechToTextError.transcriptionFailed("No transcription client registered for \(provider.displayName)")
        }
        return client
    }
}

internal final class OpenAITranscriptionProviderClient: TranscriptionProviderClient, @unchecked Sendable {
    let provider: TranscriptionProvider = .openai
    private let service: SpeechToTextService

    init(service: SpeechToTextService) {
        self.service = service
    }

    func transcribe(_ request: TranscriptionProviderRequest) async throws -> String {
        try await service.transcribeWithOpenAI(audioURL: request.audioURL)
    }
}

internal final class MiMoTranscriptionProviderClient: TranscriptionProviderClient, @unchecked Sendable {
    let provider: TranscriptionProvider = .mimo
    private let service: SpeechToTextService

    init(service: SpeechToTextService) {
        self.service = service
    }

    func transcribe(_ request: TranscriptionProviderRequest) async throws -> String {
        try await service.transcribeWithMiMo(audioURL: request.audioURL)
    }
}

internal final class GeminiTranscriptionProviderClient: TranscriptionProviderClient, @unchecked Sendable {
    let provider: TranscriptionProvider = .gemini
    private let service: SpeechToTextService

    init(service: SpeechToTextService) {
        self.service = service
    }

    func transcribe(_ request: TranscriptionProviderRequest) async throws -> String {
        try await service.transcribeWithGemini(audioURL: request.audioURL)
    }
}

internal final class LocalWhisperTranscriptionProviderClient: TranscriptionProviderClient, @unchecked Sendable {
    let provider: TranscriptionProvider = .local
    private let service: SpeechToTextService

    init(service: SpeechToTextService) {
        self.service = service
    }

    func transcribe(_ request: TranscriptionProviderRequest) async throws -> String {
        guard let model = request.whisperModel else {
            throw SpeechToTextError.transcriptionFailed("Whisper model required for local transcription")
        }
        return try await service.transcribeWithLocal(audioURL: request.audioURL, model: model)
    }
}

internal final class ParakeetTranscriptionProviderClient: TranscriptionProviderClient, @unchecked Sendable {
    let provider: TranscriptionProvider = .parakeet
    private let service: SpeechToTextService

    init(service: SpeechToTextService) {
        self.service = service
    }

    func transcribe(_ request: TranscriptionProviderRequest) async throws -> String {
        try await service.transcribeWithParakeet(audioURL: request.audioURL)
    }
}
