import SwiftUI
import AppKit

internal extension ContentView {
    func startRecording() {
        if !audioRecorder.hasPermission {
            permissionManager.requestPermissionWithEducation()
            return
        }

        // If the user selected local Whisper, ensure the model download has started so recording can proceed
        // and transcription can wait on the download if needed.
        if transcriptionProvider == .local {
            startWhisperModelDownloadIfNeeded(selectedWhisperModel)
        }
        
        lastAudioURL = nil
        streamingDraftText = ""
        LiveDictationCoordinator.shared.cancel()
        
        let success = audioRecorder.startRecording()
        if !success {
            errorMessage = LocalizedStrings.Errors.failedToStartRecording
            showError = true
            LiveDictationCoordinator.shared.cancel()
            return
        }

        let targetApp = findValidTargetApp()
        LiveDictationCoordinator.shared.beginIfNeeded(
            targetApp: targetApp,
            updateHandler: { text, _ in
                streamingDraftText = text
            }
        )
    }
    
    func stopAndProcess() {
        processingTask?.cancel()
        NotificationCenter.default.post(name: .recordingStopped, object: nil)
        
        let shouldHintThisRun = !hasShownFirstModelUseHint && isLocalModelInvocationPlanned()
        if shouldHintThisRun { showFirstModelUseHint = true }

        processingTask = Task { @MainActor in
            let processStart = Date()
            isProcessing = true
            transcriptionStartTime = Date()
            progressMessage = L10n.Recording.preparingAudio
            
            do {
                try Task.checkCancellation()
                guard let audioURL = audioRecorder.stopRecording() else {
                    throw NSError(domain: "AudioRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: LocalizedStrings.Errors.failedToGetRecordingURL])
                }
                let sessionDuration = audioRecorder.lastRecordingDuration
                
                guard !audioURL.path.isEmpty else {
                    throw NSError(domain: "AudioRecorder", code: 2, userInfo: [NSLocalizedDescriptionKey: LocalizedStrings.Errors.recordingURLEmpty])
                }
                
                lastAudioURL = audioURL
                try Task.checkCancellation()

                let streamingFinishStart = Date()
                let streamedText = await LiveDictationCoordinator.shared.finishRecognition(finalizeLiveText: false)
                let didInsertLiveText = LiveDictationCoordinator.shared.hasInsertedLiveText
                let streamingFinalizeTime = streamedText == nil
                    ? nil
                    : Date().timeIntervalSince(streamingFinishStart)
                
                var modelReadyTime: TimeInterval?
                let shouldUseStreamedFinalText = streamedText != nil
                    && TranscriptionSettingsStore.shared.transcriptionLanguage.canUseAppleStreamingAsFinalText

                if !shouldUseStreamedFinalText, transcriptionProvider == .local {
                    let modelReadyStart = Date()
                    try await ensureWhisperModelIsReadyForTranscription(selectedWhisperModel)
                    modelReadyTime = Date().timeIntervalSince(modelReadyStart)
                }

                let request = TranscriptionPipelineRequest(
                    audioURL: audioURL,
                    provider: transcriptionProvider,
                    whisperModel: transcriptionProvider == .local ? selectedWhisperModel : nil,
                    duration: sessionDuration,
                    estimatedDuration: nil,
                    sourceAppInfo: currentSourceAppInfo(),
                    modelReadyTime: modelReadyTime,
                    processStart: processStart
                )

                let result: TranscriptionPipelineResult
                if shouldUseStreamedFinalText, let streamedText {
                    progressMessage = L10n.Recording.finalizingStreaming
                    result = try await transcriptionPipeline.runPretranscribed(
                        request,
                        rawText: streamedText,
                        asrTime: streamingFinalizeTime ?? 0,
                        progressHandler: { progressMessage = $0 }
                    )
                } else {
                    result = try await transcriptionPipeline.run(
                        request,
                        progressHandler: { progressMessage = $0 }
                    )
                }

                if didInsertLiveText {
                    await LiveDictationCoordinator.shared.finishLiveText(with: result.text)
                }

                LiveDictationCoordinator.shared.cancel()

                await MainActor.run {
                    transcriptionStartTime = nil
                    streamingDraftText = ""
                    showConfirmationAndPaste(
                        text: result.text,
                        recordID: result.savedRecordID,
                        processStart: result.processStart,
                        shouldPasteAutomatically: !didInsertLiveText
                    )
                    if shouldHintThisRun { hasShownFirstModelUseHint = true; showFirstModelUseHint = false }
                }
            } catch is CancellationError {
                await MainActor.run {
                    LiveDictationCoordinator.shared.cancel()
                    streamingDraftText = ""
                    isProcessing = false
                    transcriptionStartTime = nil
                    if shouldHintThisRun { hasShownFirstModelUseHint = true; showFirstModelUseHint = false }
                }
            } catch {
                LiveDictationCoordinator.shared.cancel()
                streamingDraftText = ""
                if case let SpeechToTextError.localTranscriptionFailed(inner) = error,
                   let lwError = inner as? LocalWhisperError,
                   lwError == .modelNotDownloaded {
                    await MainActor.run {
                        errorMessage = "Local Whisper model not downloaded. Opening Settings…"
                        showError = true
                        isProcessing = false
                        transcriptionStartTime = nil
                        DashboardWindowManager.shared.showDashboardWindow(selectedNav: .providers)
                        if shouldHintThisRun { hasShownFirstModelUseHint = true; showFirstModelUseHint = false }
                    }
                } else if let pe = error as? ParakeetError, pe == .modelNotReady {
                    await MainActor.run {
                        errorMessage = "Parakeet model not downloaded. Opening Settings…"
                        showError = true
                        isProcessing = false
                        transcriptionStartTime = nil
                        DashboardWindowManager.shared.showDashboardWindow(selectedNav: .providers)
                        if shouldHintThisRun { hasShownFirstModelUseHint = true; showFirstModelUseHint = false }
                    }
                } else {
                    await MainActor.run {
                        errorMessage = error.localizedDescription
                        showError = true
                        isProcessing = false
                        transcriptionStartTime = nil
                        if shouldHintThisRun { hasShownFirstModelUseHint = true; showFirstModelUseHint = false }
                    }
                }
            }
        }
    }

    func transcribeExternalAudioFile(_ audioURL: URL) {
        processingTask?.cancel()

        let shouldHintThisRun = !hasShownFirstModelUseHint && isLocalModelInvocationPlanned()
        if shouldHintThisRun { showFirstModelUseHint = true }

        processingTask = Task { @MainActor in
            let processStart = Date()
            isProcessing = true
            transcriptionStartTime = Date()
            progressMessage = L10n.Recording.transcribingFile

            do {
                try Task.checkCancellation()
                lastAudioURL = audioURL
                try Task.checkCancellation()

                var modelReadyTime: TimeInterval?
                if transcriptionProvider == .local {
                    let modelReadyStart = Date()
                    try await ensureWhisperModelIsReadyForTranscription(selectedWhisperModel)
                    modelReadyTime = Date().timeIntervalSince(modelReadyStart)
                }

                try Task.checkCancellation()

                let fileAttributes = try? FileManager.default.attributesOfItem(atPath: audioURL.path)
                let fileSize = (fileAttributes?[.size] as? Int64) ?? 0
                let estimatedDuration = TimeInterval(fileSize) / 16000.0

                let result = try await transcriptionPipeline.run(
                    TranscriptionPipelineRequest(
                        audioURL: audioURL,
                        provider: transcriptionProvider,
                        whisperModel: transcriptionProvider == .local ? selectedWhisperModel : nil,
                        duration: nil,
                        estimatedDuration: estimatedDuration,
                        sourceAppInfo: currentSourceAppInfo(),
                        modelReadyTime: modelReadyTime,
                        processStart: processStart
                    ),
                    progressHandler: { progressMessage = $0 }
                )

                await MainActor.run {
                    transcriptionStartTime = nil
                    showConfirmationAndPaste(
                        text: result.text,
                        recordID: result.savedRecordID,
                        processStart: result.processStart
                    )
                    if shouldHintThisRun { hasShownFirstModelUseHint = true; showFirstModelUseHint = false }
                }
            } catch is CancellationError {
                await MainActor.run {
                    isProcessing = false
                    transcriptionStartTime = nil
                    if shouldHintThisRun { hasShownFirstModelUseHint = true; showFirstModelUseHint = false }
                }
            } catch {
                if case let SpeechToTextError.localTranscriptionFailed(inner) = error,
                   let lwError = inner as? LocalWhisperError,
                   lwError == .modelNotDownloaded {
                    await MainActor.run {
                        errorMessage = "Local Whisper model not downloaded. Opening Settings…"
                        showError = true
                        isProcessing = false
                        transcriptionStartTime = nil
                        DashboardWindowManager.shared.showDashboardWindow(selectedNav: .providers)
                        if shouldHintThisRun { hasShownFirstModelUseHint = true; showFirstModelUseHint = false }
                    }
                } else if let pe = error as? ParakeetError, pe == .modelNotReady {
                    await MainActor.run {
                        errorMessage = "Parakeet model not downloaded. Opening Settings…"
                        showError = true
                        isProcessing = false
                        transcriptionStartTime = nil
                        DashboardWindowManager.shared.showDashboardWindow(selectedNav: .providers)
                        if shouldHintThisRun { hasShownFirstModelUseHint = true; showFirstModelUseHint = false }
                    }
                } else {
                    await MainActor.run {
                        errorMessage = error.localizedDescription
                        showError = true
                        isProcessing = false
                        transcriptionStartTime = nil
                        if shouldHintThisRun { hasShownFirstModelUseHint = true; showFirstModelUseHint = false }
                    }
                }
            }
        }
    }

    func showConfirmationAndPaste(
        text: String,
        recordID: UUID? = nil,
        processStart: Date? = nil,
        shouldPasteAutomatically: Bool = true
    ) {
        showSuccess = true
        isProcessing = false
        soundManager.playCompletionSound()
        
        if TranscriptionSettingsStore.shared.isSmartPasteEnabled, shouldPasteAutomatically {
            if !awaitingSemanticPaste {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    performUserTriggeredPaste(recordID: recordID, processStart: processStart, pasteStart: Date())
                }
            }
        } else {
            updateTimingAfterPaste(recordID: recordID, processStart: processStart, pasteStart: nil)
            NotificationCenter.default.post(name: .restoreFocusToPreviousApp, object: nil)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                let recordWindow = NSApp.windows.first { window in
                    window.title == AppIdentity.recordingWindowTitle
                }
                
                if let window = recordWindow {
                    window.orderOut(nil)
                } else {
                    NSApplication.shared.keyWindow?.orderOut(nil)
                }
                
                NotificationCenter.default.post(name: .restoreFocusToPreviousApp, object: nil)
                showSuccess = false
            }
        }
    }
    
    func retryLastTranscription() {
        guard !isProcessing else { return }
        
        guard let audioURL = lastAudioURL else {
            errorMessage = "No audio file available to retry. Please record again."
            showError = true
            return
        }
        
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            errorMessage = "Audio file no longer exists. Please record again."
            showError = true
            lastAudioURL = nil
            return
        }
        
        processingTask?.cancel()
        
        processingTask = Task { @MainActor in
            let processStart = Date()
            isProcessing = true
            transcriptionStartTime = Date()
            progressMessage = "Retrying transcription..."
            
            do {
                try Task.checkCancellation()

                if transcriptionProvider == .local {
                    try await ensureWhisperModelIsReadyForTranscription(selectedWhisperModel)
                }

                let result = try await transcriptionPipeline.run(
                    TranscriptionPipelineRequest(
                        audioURL: audioURL,
                        provider: transcriptionProvider,
                        whisperModel: transcriptionProvider == .local ? selectedWhisperModel : nil,
                        duration: nil,
                        estimatedDuration: nil,
                        sourceAppInfo: currentSourceAppInfo(),
                        modelReadyTime: nil,
                        processStart: processStart
                    ),
                    progressHandler: { progressMessage = $0 }
                )

                transcriptionStartTime = nil
                showConfirmationAndPaste(
                    text: result.text,
                    recordID: result.savedRecordID,
                    processStart: result.processStart
                )
            } catch is CancellationError {
                await MainActor.run {
                    isProcessing = false
                    transcriptionStartTime = nil
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isProcessing = false
                    transcriptionStartTime = nil
                }
            }
        }
    }
    
    func showLastAudioFile() {
        guard let audioURL = lastAudioURL else {
            errorMessage = "No audio file available to show."
            showError = true
            return
        }
        
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            errorMessage = "Audio file no longer exists."
            showError = true
            lastAudioURL = nil
            return
        }
        
        NSWorkspace.shared.selectFile(audioURL.path, inFileViewerRootedAtPath: audioURL.deletingLastPathComponent().path)
    }
    
    private func isLocalModelInvocationPlanned() -> Bool {
        if transcriptionProvider == .local || transcriptionProvider == .parakeet { return true }
        let mode = TranscriptionSettingsStore.shared.semanticCorrectionMode
        if mode == .localMLX { return true }
        return false
    }

    func startWhisperModelDownloadIfNeeded(_ model: WhisperModel) {
        guard !WhisperKitStorage.isModelDownloaded(model) else { return }
        guard !(modelManager.downloadStages[model]?.isActive ?? false) else { return }
        guard !modelManager.downloadingModels.contains(model) else { return }

        Task {
            do {
                try await modelManager.downloadModel(model)
                await modelManager.refreshModelStates()
            } catch {
                // Don't alert while recording; the transcription flow will surface errors if the model is still missing.
            }
        }
    }

    private func ensureWhisperModelIsReadyForTranscription(_ model: WhisperModel) async throws {
        if WhisperKitStorage.isModelDownloaded(model) { return }

        await MainActor.run {
            progressMessage = "Downloading \(model.displayName) model…"
        }

        do {
            try await modelManager.downloadModel(model)
            await modelManager.refreshModelStates()
        } catch let err as ModelError where err == .alreadyDownloading {
            try await waitForWhisperModelDownload(model)
        }

        if !WhisperKitStorage.isModelDownloaded(model) {
            throw LocalWhisperError.modelNotDownloaded
        }
    }

    private func waitForWhisperModelDownload(_ model: WhisperModel) async throws {
        let timeout: TimeInterval = 20 * 60 // 20 minutes
        let startedAt = Date()
        var didRetry = false

        while true {
            try Task.checkCancellation()

            if WhisperKitStorage.isModelDownloaded(model) { return }

            if Date().timeIntervalSince(startedAt) > timeout {
                throw ModelError.downloadTimeout
            }

            let stage = await MainActor.run { modelManager.downloadStages[model] }
            if let stage {
                await MainActor.run {
                    switch stage {
                    case .preparing:
                        progressMessage = "Preparing \(model.displayName) model…"
                    case .downloading:
                        progressMessage = "Downloading \(model.displayName) model…"
                    case .processing:
                        progressMessage = "Processing \(model.displayName) model…"
                    case .completing:
                        progressMessage = "Finalizing \(model.displayName) model…"
                    case .ready:
                        progressMessage = "Model ready"
                    case .failed(let message):
                        progressMessage = "Download failed: \(message)"
                    }
                }

                if case .failed(let message) = stage {
                    throw SpeechToTextError.transcriptionFailed(message)
                }
            } else {
                // Stage may be cleared after a failure; retry once.
                if !didRetry {
                    didRetry = true
                    do {
                        try await modelManager.downloadModel(model)
                        continue
                    } catch {
                        // Fall through to keep waiting/polling with best-effort messaging.
                    }
                }
                await MainActor.run {
                    progressMessage = "Downloading \(model.displayName) model…"
                }
            }

            try await Task.sleep(for: .milliseconds(250))
        }
    }
}
