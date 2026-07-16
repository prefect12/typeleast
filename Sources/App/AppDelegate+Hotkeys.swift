import AppKit
import os.log

internal extension AppDelegate {
    func configureShortcutMonitors() {
        pressAndHoldMonitor?.stop()
        pressAndHoldMonitor = nil
        isHoldRecordingActive = false
        LiveDictationCoordinator.shared.cancel()

        let newConfiguration = PressAndHoldSettings.configuration()
        pressAndHoldConfiguration = newConfiguration

        guard newConfiguration.enabled else { return }

        let keyUpHandler: (() -> Void)? = (newConfiguration.mode == .hold) ? { [weak self] in
            self?.handlePressAndHoldKeyUp()
        } : nil

        let monitor = PressAndHoldKeyMonitor(
            configuration: newConfiguration,
            keyDownHandler: { [weak self] in
                self?.handlePressAndHoldKeyDown()
            },
            keyUpHandler: keyUpHandler
        )

        pressAndHoldMonitor = monitor
        monitor.start()
    }

    private func handlePressAndHoldKeyDown() {
        switch pressAndHoldConfiguration.mode {
        case .hold:
            startRecordingFromPressAndHold()
        case .toggle, .doubleTapToggle:
            handleHotkey(source: .pressAndHold)
        }
    }

    private func handlePressAndHoldKeyUp() {
        guard pressAndHoldConfiguration.mode == .hold else { return }
        stopRecordingFromPressAndHold()
    }

    private func startRecordingFromPressAndHold() {
        guard let recorder = audioRecorder else { return }

        if recorder.isRecording {
            isHoldRecordingActive = true
            return
        }

        if !recorder.hasPermission {
            showRecordingWindowForProcessing()
            return
        }

        let targetApp = captureLiveDictationTargetApp()
        if beginShortcutRecording(recorder: recorder, targetApp: targetApp) {
            isHoldRecordingActive = true
            updateMenuBarIcon(isRecording: true)
            SoundManager().playRecordingStartSound()
            showRecordingWindowForProcessing()
        } else {
            LiveDictationCoordinator.shared.cancel()
            isHoldRecordingActive = false
            showRecordingWindowForProcessing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    NotificationCenter.default.post(
                        name: .recordingStartFailed,
                        object: nil
                    )
                }
            }
        }
    }

    private func stopRecordingFromPressAndHold() {
        guard isHoldRecordingActive else { return }
        guard let recorder = audioRecorder, recorder.isRecording else {
            isHoldRecordingActive = false
            return
        }

        isHoldRecordingActive = false
        updateMenuBarIcon(isRecording: false)

        showRecordingWindowForProcessing {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NotificationCenter.default.post(name: .spaceKeyPressed, object: nil)
            }
        }
    }

    func handleHotkey(source: HotkeyTriggerSource) {
        let isContinuousMode = UserDefaults.standard.bool(forKey: AppDefaults.Keys.immediateRecording)

        if isContinuousMode || source == .pressAndHold {
            toggleRecordingFromShortcut()
        } else {
            startRecordingFromPressAndHold()
        }
    }

    func handleHotkeyRelease(source: HotkeyTriggerSource) {
        guard source == .standardHotkey else { return }
        guard !UserDefaults.standard.bool(forKey: AppDefaults.Keys.immediateRecording) else { return }

        stopRecordingFromPressAndHold()
    }

    private func toggleRecordingFromShortcut() {
        guard let recorder = audioRecorder else {
            Logger.app.error("AudioRecorder not available for shortcut recording")
            toggleRecordWindow()
            return
        }

        if recorder.isRecording {
            updateMenuBarIcon(isRecording: false)
            if recordingWindow == nil || recordingWindow?.isVisible == false {
                toggleRecordWindow()
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NotificationCenter.default.post(name: .spaceKeyPressed, object: nil)
            }
        } else {
            if !recorder.hasPermission {
                toggleRecordWindow()
                return
            }

            let targetApp = captureLiveDictationTargetApp()
            if beginShortcutRecording(recorder: recorder, targetApp: targetApp) {
                updateMenuBarIcon(isRecording: true)
                SoundManager().playRecordingStartSound()
                showRecordingWindowForProcessing()
            } else {
                LiveDictationCoordinator.shared.cancel()
                toggleRecordWindow()
                NotificationCenter.default.post(
                    name: .recordingStartFailed,
                    object: nil
                )
            }
        }
    }

    private func beginShortcutRecording(
        recorder: AudioRecorder,
        targetApp: NSRunningApplication?
    ) -> Bool {
        if TranscriptionSettingsStore.shared.transcriptionProvider == .openAIRealtime {
            LiveDictationCoordinator.shared.beginIfNeeded(targetApp: targetApp)
            let started = recorder.startRecording { data in
                Task { @MainActor in LiveDictationCoordinator.shared.appendPCM16AudioData(data) }
            }
            if !started { LiveDictationCoordinator.shared.cancel() }
            return started
        }

        let started = recorder.startRecording()
        if started { LiveDictationCoordinator.shared.beginIfNeeded(targetApp: targetApp) }
        return started
    }

    private func updateMenuBarIcon(isRecording: Bool) {
        guard let button = statusItem?.button else { return }

        if isRecording {
            startRecordingAnimation()
        } else {
            stopRecordingAnimation()
            button.image = AppSetupHelper.createMenuBarIcon()
        }
    }

    private func captureLiveDictationTargetApp() -> NSRunningApplication? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              !AppIdentity.isTypeleastBundleIdentifier(frontmostApp.bundleIdentifier),
              !frontmostApp.isTerminated else {
            return WindowController.storedTargetApp
        }

        WindowController.storedTargetApp = frontmostApp
        NotificationCenter.default.post(name: .targetAppStored, object: frontmostApp)
        return frontmostApp
    }

    private func startRecordingAnimation() {
        guard let button = statusItem?.button else { return }

        stopRecordingAnimation()

        let iconSize = AppSetupHelper.getAdaptiveMenuBarIconSize()
        let config = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .medium)

        let redImage = NSImage(systemSymbolName: "microphone.circle", accessibilityDescription: "Recording")?.withSymbolConfiguration(config)
        redImage?.isTemplate = false
        let redOutlineImage = redImage?.tinted(with: .systemRed)

        let blackImage = NSImage(systemSymbolName: "microphone.circle", accessibilityDescription: "Recording")?.withSymbolConfiguration(config)
        blackImage?.isTemplate = true

        button.image = redOutlineImage

        var isRedState = true

        let queue = DispatchQueue(label: "com.typeleast.animation", qos: .background)
        let timer = DispatchSource.makeTimerSource(queue: queue)

        timer.schedule(deadline: .now(), repeating: 0.5)

        timer.setEventHandler { [weak button] in
            guard let button = button else { return }

            isRedState.toggle()

            Task { @MainActor in
                button.image = isRedState ? redOutlineImage : blackImage
            }
        }

        recordingAnimationTimer = timer
        timer.resume()
    }

    private func stopRecordingAnimation() {
        recordingAnimationTimer?.cancel()
        recordingAnimationTimer = nil
    }

    @objc func onRecordingStopped() {
        updateMenuBarIcon(isRecording: false)
    }
}
