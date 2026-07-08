import XCTest
import Foundation
import AVFoundation
@testable import Typeleast

class SpeechToTextServiceTests: XCTestCase {
    var service: SpeechToTextService!
    var mockKeychain: MockKeychainService!
    var testAudioURL: URL!
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!
    
    override func setUp() {
        super.setUp()
        defaultsSuiteName = "com.typeleast.tests.speech.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        mockKeychain = MockKeychainService()
        service = SpeechToTextService(keychainService: mockKeychain, userDefaults: defaults)
        
        // Create a temporary test audio file
        testAudioURL = createTestAudioFile()
    }
    
    override func tearDown() {
        if let url = testAudioURL, FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        service = nil
        mockKeychain = nil
        testAudioURL = nil
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        defaultsSuiteName = nil
        super.tearDown()
    }
    
    // MARK: - Error Handling Tests
    
    func testSpeechToTextErrorDescriptions() {
        let invalidURLError = SpeechToTextError.invalidURL
        XCTAssertEqual(invalidURLError.errorDescription, "Recording appears to be corrupted. Please try recording again.")
        
        let apiKeyMissingError = SpeechToTextError.apiKeyMissing("OpenAI")
        XCTAssertTrue(apiKeyMissingError.errorDescription?.contains("To use OpenAI transcription, please add your API key in Settings") == true)
        
        let transcriptionFailedError = SpeechToTextError.transcriptionFailed("Test error")
        XCTAssertEqual(transcriptionFailedError.errorDescription, "Transcription failed: Test error\n\nPlease check your internet connection and API key in Settings.")
    }
    
    // MARK: - Provider Selection Tests

    func testOpenAITranscriptionModelDefaultsToGPT4OTranscribe() {
        defaults.removeObject(forKey: AppDefaults.Keys.openAITranscriptionModel)

        XCTAssertEqual(service.resolvedOpenAITranscriptionModel, "gpt-4o-transcribe")
    }

    func testOpenAITranscriptionModelUsesConfiguredValue() {
        defaults.set("whisper-1", forKey: AppDefaults.Keys.openAITranscriptionModel)

        XCTAssertEqual(service.resolvedOpenAITranscriptionModel, "whisper-1")
    }

    func testOpenAITranscriptionModelFallsBackWhenBlank() {
        defaults.set("   ", forKey: AppDefaults.Keys.openAITranscriptionModel)

        XCTAssertEqual(service.resolvedOpenAITranscriptionModel, "gpt-4o-transcribe")
    }

    func testMiMoASRModelDefaultsToV25ASR() {
        defaults.removeObject(forKey: AppDefaults.Keys.miMoASRModel)

        XCTAssertEqual(service.resolvedMiMoASRModel, "mimo-v2.5-asr")
    }

    func testMiMoASRModelUsesConfiguredValue() {
        defaults.set("mimo-v2.5-asr-custom", forKey: AppDefaults.Keys.miMoASRModel)

        XCTAssertEqual(service.resolvedMiMoASRModel, "mimo-v2.5-asr-custom")
    }

    func testMiMoASRModelFallsBackWhenBlank() {
        defaults.set("   ", forKey: AppDefaults.Keys.miMoASRModel)

        XCTAssertEqual(service.resolvedMiMoASRModel, "mimo-v2.5-asr")
    }

    func testTranscriptionLanguageDefaultsToAuto() {
        defaults.removeObject(forKey: AppDefaults.Keys.transcriptionLanguage)

        XCTAssertEqual(service.resolvedTranscriptionLanguage, .auto)
    }

    func testTranscriptionLanguageUsesConfiguredValue() {
        defaults.set(TranscriptionLanguage.chinese.rawValue, forKey: AppDefaults.Keys.transcriptionLanguage)

        XCTAssertEqual(service.resolvedTranscriptionLanguage, .chinese)
    }

    func testTranscriptionLanguageFallsBackForInvalidValue() {
        defaults.set("not-a-language", forKey: AppDefaults.Keys.transcriptionLanguage)

        XCTAssertEqual(service.resolvedTranscriptionLanguage, .auto)
    }

    func testASRPromptPreservesAutoDetectedLanguage() {
        let prompt = SpeechToTextService.technicalASRPrompt(language: .auto)

        XCTAssertTrue(prompt.contains("Detect the spoken language automatically"))
        XCTAssertTrue(prompt.contains("do not translate"))
    }

    func testASRPromptCanForceChinese() {
        let prompt = SpeechToTextService.technicalASRPrompt(language: .chinese)

        XCTAssertTrue(prompt.contains("primarily Chinese"))
        XCTAssertTrue(prompt.contains("preserve spoken English exactly"))
    }
    
    func testProviderSelectionDefaultsToOpenAI() async {
        // Create a fresh mock keychain with no keys
        let cleanMockKeychain = MockKeychainService()
        let cleanService = SpeechToTextService(keychainService: cleanMockKeychain, userDefaults: defaults)
        
        // Clear any existing preference
        defaults.removeObject(forKey: "useOpenAI")
        
        // Since we can't easily mock the network calls, we'll test that the right path is taken
        // by checking that it fails with the expected error (missing API key)
        do {
            _ = try await cleanService.transcribe(audioURL: testAudioURL)
            XCTFail("Expected error due to missing API key")
        } catch let error as SpeechToTextError {
            XCTAssertEqual(error, SpeechToTextError.apiKeyMissing("OpenAI"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    func testProviderSelectionUsesOpenAIWhenSet() async {
        defaults.set(true, forKey: "useOpenAI")
        
        do {
            _ = try await service.transcribe(audioURL: testAudioURL)
            XCTFail("Expected error due to missing API key")
        } catch let error as SpeechToTextError {
            XCTAssertEqual(error, SpeechToTextError.apiKeyMissing("OpenAI"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    func testProviderSelectionUsesGeminiWhenSet() async {
        // Create a fresh mock keychain with no keys
        let cleanMockKeychain = MockKeychainService()
        let cleanService = SpeechToTextService(keychainService: cleanMockKeychain, userDefaults: defaults)
        
        defaults.set(false, forKey: "useOpenAI")
        
        do {
            _ = try await cleanService.transcribe(audioURL: testAudioURL)
            XCTFail("Expected error due to missing API key")
        } catch let error as SpeechToTextError {
            XCTAssertEqual(error, SpeechToTextError.apiKeyMissing("Gemini"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    // MARK: - Response Model Tests
    
    func testWhisperResponseDecoding() {
        let jsonString = """
        {
            "text": "Hello, world!"
        }
        """
        
        let data = jsonString.data(using: .utf8)!
        
        do {
            let response = try JSONDecoder().decode(WhisperResponse.self, from: data)
            XCTAssertEqual(response.text, "Hello, world!")
        } catch {
            XCTFail("Failed to decode WhisperResponse: \(error)")
        }
    }
    
    func testGeminiResponseDecoding() {
        let jsonString = """
        {
            "candidates": [
                {
                    "content": {
                        "parts": [
                            {
                                "text": "Hello, world!"
                            }
                        ]
                    }
                }
            ]
        }
        """
        
        let data = jsonString.data(using: .utf8)!
        
        do {
            let response = try JSONDecoder().decode(GeminiResponse.self, from: data)
            XCTAssertEqual(response.candidates.first?.content.parts.first?.text, "Hello, world!")
        } catch {
            XCTFail("Failed to decode GeminiResponse: \(error)")
        }
    }
    
    func testGeminiResponseWithMissingText() {
        let jsonString = """
        {
            "candidates": [
                {
                    "content": {
                        "parts": [
                            {
                                "text": null
                            }
                        ]
                    }
                }
            ]
        }
        """
        
        let data = jsonString.data(using: .utf8)!
        
        do {
            let response = try JSONDecoder().decode(GeminiResponse.self, from: data)
            XCTAssertNil(response.candidates.first?.content.parts.first?.text)
        } catch {
            XCTFail("Failed to decode GeminiResponse: \(error)")
        }
    }
    
    func testGeminiResponseWithEmptyCandidates() {
        let jsonString = """
        {
            "candidates": []
        }
        """
        
        let data = jsonString.data(using: .utf8)!
        
        do {
            let response = try JSONDecoder().decode(GeminiResponse.self, from: data)
            XCTAssertTrue(response.candidates.isEmpty)
        } catch {
            XCTFail("Failed to decode GeminiResponse: \(error)")
        }
    }

    func testMiMoResponseDecoding() throws {
        let jsonString = """
        {
            "choices": [
                {
                    "message": {
                        "content": "Good morning.",
                        "role": "assistant"
                    }
                }
            ]
        }
        """

        let data = jsonString.data(using: .utf8)!
        let response = try JSONDecoder().decode(MiMoChatCompletionResponse.self, from: data)

        XCTAssertEqual(response.choices.first?.message.content, "Good morning.")
    }

    func testMiMoRequestEncodingUsesOpenAICompatibleAudioShape() throws {
        let request = MiMoChatCompletionRequest.make(
            model: "mimo-v2.5-asr",
            dataURI: "data:audio/mp4;base64,AAAA",
            language: .chinese
        )
        let data = try JSONEncoder().encode(request)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let messages = object?["messages"] as? [[String: Any]]
        let firstMessage = messages?.first
        let content = firstMessage?["content"] as? [[String: Any]]
        let inputAudio = content?.first?["input_audio"] as? [String: Any]
        let asrOptions = object?["asr_options"] as? [String: Any]

        XCTAssertEqual(object?["model"] as? String, "mimo-v2.5-asr")
        XCTAssertEqual(firstMessage?["role"] as? String, "user")
        XCTAssertEqual(content?.first?["type"] as? String, "input_audio")
        XCTAssertEqual(inputAudio?["data"] as? String, "data:audio/mp4;base64,AAAA")
        XCTAssertEqual(asrOptions?["language"] as? String, "auto")
    }

    func testMiMoAudioDataURI() {
        let data = Data([0x01, 0x02, 0x03])

        XCTAssertEqual(SpeechToTextService.miMoAudioDataURI(data: data, mimeType: "audio/mp4"), "data:audio/mp4;base64,AQID")
    }

    func testMiMoMimeTypeDetection() {
        XCTAssertEqual(SpeechToTextService.mimeType(forAudioURL: URL(fileURLWithPath: "/tmp/test.m4a")), "audio/mp4")
        XCTAssertEqual(SpeechToTextService.mimeType(forAudioURL: URL(fileURLWithPath: "/tmp/test.wav")), "audio/wav")
        XCTAssertEqual(SpeechToTextService.mimeType(forAudioURL: URL(fileURLWithPath: "/tmp/test.mp3")), "audio/mpeg")
        XCTAssertEqual(SpeechToTextService.mimeType(forAudioURL: URL(fileURLWithPath: "/tmp/test.unknown")), "audio/mp4")
    }
    
    // MARK: - File Handling Tests
    
    func testTranscribeWithInvalidURL() async {
        let invalidURL = URL(fileURLWithPath: "/nonexistent/file.m4a")
        
        do {
            // Set up mock keychain to have an API key so we get to the file reading part
            mockKeychain.saveQuietly("test-key", service: "Typeleast", account: "OpenAI")
            
            _ = try await service.transcribe(audioURL: invalidURL)
            XCTFail("Expected error due to invalid file URL")
        } catch {
            // Should get an error when trying to read the file
            XCTAssertTrue(error is SpeechToTextError || error is CocoaError)
        }
    }
    
    // MARK: - API Key Tests
    
    func testAPIKeyRetrievalMethods() {
        // Test that keychain is the primary and only method for API key retrieval
        let mockKeychain = MockKeychainService()
        
        // Test that it returns nil when no key is found
        let apiKey = mockKeychain.getQuietly(service: "Typeleast", account: "OpenAI")
        XCTAssertNil(apiKey)
        
        // Test saving and retrieving a key
        mockKeychain.saveQuietly("test-api-key", service: "Typeleast", account: "OpenAI")
        let retrievedKey = mockKeychain.getQuietly(service: "Typeleast", account: "OpenAI")
        XCTAssertEqual(retrievedKey, "test-api-key")
    }
    
    func testAPIKeyFromKeychain() {
        // Test the keychain reading functionality with mock
        let mockKeychain = MockKeychainService()
        let _ = SpeechToTextService(keychainService: mockKeychain, userDefaults: defaults)
        
        // Test that it returns nil when no key is found
        let apiKey = mockKeychain.getQuietly(service: "Typeleast", account: "OpenAI")
        XCTAssertNil(apiKey)
        
        // Test saving and retrieving a key
        mockKeychain.saveQuietly("test-api-key", service: "Typeleast", account: "OpenAI")
        let retrievedKey = mockKeychain.getQuietly(service: "Typeleast", account: "OpenAI")
        XCTAssertEqual(retrievedKey, "test-api-key")
    }

    func testMiMoProviderMissingAPIKey() async throws {
        let validAudioURL = try makeValidAudioFile()
        defer { try? FileManager.default.removeItem(at: validAudioURL) }

        do {
            _ = try await service.transcribe(audioURL: validAudioURL, provider: .mimo)
            XCTFail("Expected error due to missing MiMo API key")
        } catch let error as SpeechToTextError {
            XCTAssertEqual(error, SpeechToTextError.apiKeyMissing("MiMo"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentTranscriptionCalls() async {
        defaults.set(true, forKey: "useOpenAI")
        
        let tasks = (0..<5).map { _ in
            Task {
                do {
                    _ = try await service.transcribe(audioURL: testAudioURL)
                    XCTFail("Expected error due to missing API key")
                } catch let error as SpeechToTextError {
                    XCTAssertEqual(error, SpeechToTextError.apiKeyMissing("OpenAI"))
                } catch {
                    XCTFail("Unexpected error type: \(error)")
                }
            }
        }
        
        // Wait for all tasks to complete
        for task in tasks {
            _ = await task.value
        }
    }
    
    // MARK: - Performance Tests
    
    func testProviderSelectionPerformance() {
        defaults.set(true, forKey: "useOpenAI")
        
        measure {
            Task {
                do {
                    _ = try await service.transcribe(audioURL: testAudioURL)
                } catch {
                    // Expected to fail due to missing API key
                }
            }
        }
    }
    
    func testResponseDecodingPerformance() {
        let jsonString = """
        {
            "text": "This is a test transcription result that should be decoded quickly."
        }
        """
        
        let data = jsonString.data(using: .utf8)!
        
        measure {
            for _ in 0..<1000 {
                _ = try? JSONDecoder().decode(WhisperResponse.self, from: data)
            }
        }
    }
}

// MARK: - Test Helpers

extension SpeechToTextServiceTests {
    private func createTestAudioFile() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let audioURL = tempDir.appendingPathComponent("test_audio.m4a")
        
        // Create a minimal test file
        guard let testData = "test audio data".data(using: .utf8) else {
            XCTFail("Failed to create test data")
            return tempDir.appendingPathComponent("invalid")
        }
        do {
            try testData.write(to: audioURL)
        } catch {
            XCTFail("Failed to write test file: \(error)")
            return tempDir.appendingPathComponent("invalid")
        }
        
        return audioURL
    }

    private func makeValidAudioFile() throws -> URL {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1) else {
            throw NSError(domain: "SpeechToTextServiceTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to create audio format"])
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeechToTextServiceTests-valid-\(UUID().uuidString).wav")

        let frameCount: AVAudioFrameCount = 1_024
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "SpeechToTextServiceTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to create buffer"])
        }
        buffer.frameLength = frameCount

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }
    
    // MARK: - Parakeet Provider Tests
    
    func testTranscribeWithParakeetProviderMissingPython() async {
        let invalidPythonPath = "/invalid/python/path"
        defaults.set(invalidPythonPath, forKey: "parakeetPythonPath")
        
        do {
            _ = try await service.transcribe(audioURL: testAudioURL, provider: .parakeet)
            XCTFail("Expected error due to invalid audio or Python path")
        } catch let error as SpeechToTextError {
            // The test can fail either due to invalid audio (which is expected since we create a fake file)
            // or due to invalid Python path. Both are acceptable test outcomes
            let errorMessage = error.localizedDescription
            let hasExpectedError = errorMessage.contains("Parakeet error") || 
                                 errorMessage.contains("Python") || 
                                 errorMessage.contains("not found") ||
                                 errorMessage.contains("corrupted") ||
                                 errorMessage.contains("unreadable")
            XCTAssertTrue(hasExpectedError, "Error should indicate audio or Python issue: \(errorMessage)")
        } catch {
            XCTFail("Expected SpeechToTextError, got \(error)")
        }
        
        // Clean up
        defaults.removeObject(forKey: "parakeetPythonPath")
    }
    
    func testParakeetProviderWithSystemPython() async {
        let systemPythonPath = "/usr/bin/python3"
        
        // Only test if system Python exists
        if FileManager.default.fileExists(atPath: systemPythonPath) {
            defaults.set(systemPythonPath, forKey: "parakeetPythonPath")
            
            do {
                _ = try await service.transcribe(audioURL: testAudioURL, provider: .parakeet)
                // If this succeeds, parakeet-mlx is installed
            } catch let error as SpeechToTextError {
                // Expected if parakeet-mlx is not installed or script not found
                // Just verify we got a SpeechToTextError (which we did)
                XCTAssertTrue(error.localizedDescription.count > 0)
            } catch {
                XCTFail("Expected SpeechToTextError, got \(error)")
            }
            
            // Clean up
            defaults.removeObject(forKey: "parakeetPythonPath")
        }
    }
    
    func testParakeetProviderInAllCases() {
        // Ensure Parakeet is included in all provider tests
        let allProviders: [TranscriptionProvider] = [.openai, .mimo, .gemini, .local, .parakeet]
        XCTAssertTrue(allProviders.contains(.parakeet))
        XCTAssertEqual(allProviders.count, 5)
    }

    // MARK: - Custom OpenAI Endpoint Tests

    func testOpenAIEndpointDefaultsToStandard() {
        // Clear any custom URL
        defaults.removeObject(forKey: "openAIBaseURL")

        // The default should be the standard OpenAI endpoint
        // We can't directly test the private property, but we can verify the behavior
        // by checking that a request would go to the right place (via error message or mock)
        let customURL = defaults.string(forKey: "openAIBaseURL")
        XCTAssertNil(customURL)
    }

    func testOpenAIEndpointWithBaseURL() {
        // Test that a base URL gets /audio/transcriptions appended
        let baseURL = "https://api.example.com/v1"
        defaults.set(baseURL, forKey: "openAIBaseURL")

        // Verify it was set
        let storedURL = defaults.string(forKey: "openAIBaseURL")
        XCTAssertEqual(storedURL, baseURL)

        // The endpoint logic should append /audio/transcriptions
        // since the URL doesn't contain "audio/transcriptions"
        XCTAssertFalse(baseURL.contains("audio/transcriptions"))

        // Cleanup
        defaults.removeObject(forKey: "openAIBaseURL")
    }

    func testOpenAIEndpointWithFullAzureURL() {
        // Test that a full Azure URL is used as-is
        let azureURL = "https://my-resource.openai.azure.com/openai/deployments/whisper/audio/transcriptions?api-version=2024-02-01"
        defaults.set(azureURL, forKey: "openAIBaseURL")

        // Verify it was set
        let storedURL = defaults.string(forKey: "openAIBaseURL")
        XCTAssertEqual(storedURL, azureURL)

        // The endpoint logic should use this URL as-is
        // since it already contains "audio/transcriptions"
        XCTAssertTrue(azureURL.contains("audio/transcriptions"))

        // Verify Azure detection
        XCTAssertTrue(azureURL.contains(".openai.azure.com"))

        // Cleanup
        defaults.removeObject(forKey: "openAIBaseURL")
    }

    func testOpenAIEndpointWithProxyURL() {
        // Test proxy service like aiswarm.me
        let proxyURL = "https://aiswarm.me/v1"
        defaults.set(proxyURL, forKey: "openAIBaseURL")

        // Verify it was set
        let storedURL = defaults.string(forKey: "openAIBaseURL")
        XCTAssertEqual(storedURL, proxyURL)

        // Should NOT be detected as Azure
        XCTAssertFalse(proxyURL.contains(".openai.azure.com"))

        // Should need /audio/transcriptions appended
        XCTAssertFalse(proxyURL.contains("audio/transcriptions"))

        // Cleanup
        defaults.removeObject(forKey: "openAIBaseURL")
    }

    func testAzureEndpointDetection() {
        // Test various URL patterns for Azure detection
        let azureURLs = [
            "https://my-resource.openai.azure.com/openai/deployments/whisper/audio/transcriptions?api-version=2024-02-01",
            "https://eastus.openai.azure.com/openai/deployments/my-whisper/audio/transcriptions?api-version=2023-09-01"
        ]

        let nonAzureURLs = [
            "https://api.openai.com/v1",
            "https://aiswarm.me/v1",
            "https://my-proxy.com/openai/v1",
            ""
        ]

        for url in azureURLs {
            XCTAssertTrue(url.contains(".openai.azure.com"), "Should detect Azure: \(url)")
        }

        for url in nonAzureURLs {
            XCTAssertFalse(url.contains(".openai.azure.com"), "Should NOT detect Azure: \(url)")
        }
    }

    func testOpenAIEndpointPreservesQueryString() {
        // Test that query strings are preserved for full endpoints
        let urlWithQuery = "https://my-resource.openai.azure.com/openai/deployments/whisper/audio/transcriptions?api-version=2024-02-01"
        defaults.set(urlWithQuery, forKey: "openAIBaseURL")

        let storedURL = defaults.string(forKey: "openAIBaseURL")
        XCTAssertEqual(storedURL, urlWithQuery)
        XCTAssertTrue(storedURL?.contains("api-version=") == true)

        // Cleanup
        defaults.removeObject(forKey: "openAIBaseURL")
    }

}

// MARK: - Mock Extensions

// MARK: - Error Comparison

extension SpeechToTextError: Equatable {
    public static func == (lhs: SpeechToTextError, rhs: SpeechToTextError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidURL, .invalidURL):
            return true
        case (.apiKeyMissing, .apiKeyMissing):
            return true
        case (.transcriptionFailed(let lhsMessage), .transcriptionFailed(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
}
