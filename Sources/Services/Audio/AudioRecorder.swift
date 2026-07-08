import Foundation
import AVFoundation
import Combine
import os.log

@MainActor
internal class AudioRecorder: NSObject, ObservableObject {
    typealias PCM16AudioDataHandler = @Sendable (Data) -> Void

    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    @Published var hasPermission = false
    
    private var audioRecorder: AVAudioRecorder?
    private var audioEngine: AVAudioEngine?
    private var wavWriter: PCM16WAVFileWriter?
    private var recordingURL: URL?
    private var levelUpdateTimer: Timer?
    private let volumeManager: MicrophoneVolumeManager
    private let recorderFactory: (URL, [String: Any]) throws -> AVAudioRecorder
    private let dateProvider: () -> Date
    private(set) var currentSessionStart: Date?
    private(set) var lastRecordingDuration: TimeInterval?
    
    override init() {
        self.volumeManager = MicrophoneVolumeManager.shared
        self.recorderFactory = { url, settings in try AVAudioRecorder(url: url, settings: settings) }
        self.dateProvider = { Date() }
        super.init()
        setupRecorder()
        checkMicrophonePermission()
    }

    init(
        volumeManager: MicrophoneVolumeManager = .shared,
        recorderFactory: @escaping (URL, [String: Any]) throws -> AVAudioRecorder,
        dateProvider: @escaping () -> Date = { Date() }
    ) {
        self.volumeManager = volumeManager
        self.recorderFactory = recorderFactory
        self.dateProvider = dateProvider
        super.init()
        setupRecorder()
        checkMicrophonePermission()
    }
    
    private func setupRecorder() {
        // AVAudioSession is not needed on macOS
    }
    
    func checkMicrophonePermission() {
        let permissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch permissionStatus {
        case .authorized:
            self.hasPermission = true
        case .denied, .restricted:
            self.hasPermission = false
        case .notDetermined:
            // Never trigger a real system permission prompt in unit tests.
            guard !AppEnvironment.isRunningTests else {
                self.hasPermission = false
                return
            }
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor [weak self] in
                    self?.hasPermission = granted
                }
            }
        @unknown default:
            self.hasPermission = false
        }
    }
    
    func requestMicrophonePermission() {
        // Never trigger a real system permission prompt in unit tests.
        guard !AppEnvironment.isRunningTests else {
            hasPermission = false
            return
        }
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor [weak self] in
                self?.hasPermission = granted
            }
        }
    }
    
    func startRecording(pcm16AudioDataHandler: PCM16AudioDataHandler? = nil) -> Bool {
        // Check permission first
        guard hasPermission else {
            return false
        }
        
        // Prevent re-entrancy - if already recording, return false
        guard audioRecorder == nil, audioEngine == nil else {
            return false
        }
        
        // Boost microphone volume if enabled
        if UserDefaults.standard.autoBoostMicrophoneVolume {
            Task {
                await volumeManager.boostMicrophoneVolume()
            }
        }
        
        let tempPath = FileManager.default.temporaryDirectory
        let timestamp = dateProvider().timeIntervalSince1970
        let audioFilename = tempPath.appendingPathComponent(
            pcm16AudioDataHandler == nil
                ? "recording_\(timestamp).m4a"
                : "recording_\(timestamp).wav"
        )
        
        recordingURL = audioFilename

        if let pcm16AudioDataHandler {
            return startEngineRecording(
                audioFilename: audioFilename,
                pcm16AudioDataHandler: pcm16AudioDataHandler
            )
        }
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        // Note: On macOS, microphone selection is handled at the system level
        // The AVAudioRecorder will use the system's default input device
        // Users can change this in System Preferences > Sound > Input
        
        do {
            audioRecorder = try recorderFactory(audioFilename, settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            currentSessionStart = dateProvider()
            lastRecordingDuration = nil
            
            self.isRecording = true
            self.startLevelMonitoring()
            return true
        } catch {
            Logger.audioRecorder.error("Failed to start recording: \(error.localizedDescription)")
            // Restore volume if recording failed and we boosted it
            if UserDefaults.standard.autoBoostMicrophoneVolume {
                Task {
                    await volumeManager.restoreMicrophoneVolume()
                }
            }
            // Recheck permissions if recording failed
            checkMicrophonePermission()
            return false
        }
    }

    private func startEngineRecording(
        audioFilename: URL,
        pcm16AudioDataHandler: @escaping PCM16AudioDataHandler
    ) -> Bool {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            return false
        }

        do {
            let writer = try PCM16WAVFileWriter(url: audioFilename)
            inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self, writer] buffer, _ in
                guard let pcmData = RealtimeAudioPCMConverter.pcm16Mono24kData(from: buffer),
                      !pcmData.isEmpty else {
                    return
                }

                do {
                    try writer.append(pcmData)
                } catch {
                    Logger.audioRecorder.error("Failed to write realtime WAV data: \(error.localizedDescription)")
                }

                pcm16AudioDataHandler(pcmData)

                let level = Self.normalizedLevel(from: buffer)
                Task { @MainActor [weak self] in
                    self?.audioLevel = level
                }
            }

            engine.prepare()
            try engine.start()

            audioEngine = engine
            wavWriter = writer
            currentSessionStart = dateProvider()
            lastRecordingDuration = nil
            isRecording = true
            return true
        } catch {
            Logger.audioRecorder.error("Failed to start realtime recording: \(error.localizedDescription)")
            inputNode.removeTap(onBus: 0)
            wavWriter?.cancel()
            wavWriter = nil
            audioEngine = nil
            recordingURL = nil
            if UserDefaults.standard.autoBoostMicrophoneVolume {
                Task {
                    await volumeManager.restoreMicrophoneVolume()
                }
            }
            checkMicrophonePermission()
            return false
        }
    }
    
    func stopRecording() -> URL? {
        let now = dateProvider()
        let sessionDuration = currentSessionStart.map { now.timeIntervalSince($0) }
        lastRecordingDuration = sessionDuration
        currentSessionStart = nil

        if let audioEngine {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
            self.audioEngine = nil
            do {
                try wavWriter?.finish()
            } catch {
                Logger.audioRecorder.error("Failed to finalize realtime WAV recording: \(error.localizedDescription)")
            }
            wavWriter = nil
        } else {
            audioRecorder?.stop()
            audioRecorder = nil
        }
        
        // Restore microphone volume if it was boosted
        if UserDefaults.standard.autoBoostMicrophoneVolume {
            Task {
                await volumeManager.restoreMicrophoneVolume()
            }
        }
        
        // Update @Published properties on main thread
        self.isRecording = false
        self.stopLevelMonitoring()
        
        return recordingURL
    }
    
    func cleanupRecording() {
        guard let url = recordingURL else { return }
        
        // Restore microphone volume if it was boosted (in case of cancellation/cleanup)
        if UserDefaults.standard.autoBoostMicrophoneVolume {
            Task {
                await volumeManager.restoreMicrophoneVolume()
            }
        }

        currentSessionStart = nil
        lastRecordingDuration = nil
        
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Logger.audioRecorder.error("Failed to cleanup recording file: \(error.localizedDescription)")
        }
        
        recordingURL = nil
    }
    
    func cancelRecording() {
        // Stop recording and cleanup without returning URL
        if let audioEngine {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
            self.audioEngine = nil
            wavWriter?.cancel()
            wavWriter = nil
        } else {
            audioRecorder?.stop()
            audioRecorder = nil
        }
        currentSessionStart = nil
        lastRecordingDuration = nil
        
        // Restore microphone volume if it was boosted
        if UserDefaults.standard.autoBoostMicrophoneVolume {
            Task {
                await volumeManager.restoreMicrophoneVolume()
            }
        }
        
        // Update @Published properties on main thread
        self.isRecording = false
        self.stopLevelMonitoring()
        
        // Clean up the recording file
        cleanupRecording()
    }
    
    private func startLevelMonitoring() {
        // Use a more efficient approach for macOS
        levelUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let recorder = self.audioRecorder else { return }

                recorder.updateMeters()
                let normalizedLevel = self.normalizeLevel(recorder.averagePower(forChannel: 0))

                self.audioLevel = normalizedLevel
            }
        }
    }
    
    private func stopLevelMonitoring() {
        levelUpdateTimer?.invalidate()
        levelUpdateTimer = nil
        audioLevel = 0.0
    }
    
    private func normalizeLevel(_ level: Float) -> Float {
        // Convert dB to linear scale (0.0 to 1.0)
        let minDb: Float = -60.0
        let maxDb: Float = 0.0
        
        let clampedLevel = max(minDb, min(maxDb, level))
        return (clampedLevel - minDb) / (maxDb - minDb)
    }

    nonisolated private static func normalizedLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData,
              buffer.frameLength > 0 else {
            return 0
        }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        var sum: Float = 0
        var sampleCount = 0

        for channel in 0..<max(channelCount, 1) {
            let samples = channelData[channel]
            for frame in 0..<frameLength {
                let sample = samples[frame]
                sum += sample * sample
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else { return 0 }
        let rms = sqrt(sum / Float(sampleCount))
        let db = 20 * log10(max(rms, 0.000_001))
        return normalizeLevel(db)
    }

    nonisolated private static func normalizeLevel(_ level: Float) -> Float {
        let minDb: Float = -60.0
        let maxDb: Float = 0.0
        let clampedLevel = max(minDb, min(maxDb, level))
        return (clampedLevel - minDb) / (maxDb - minDb)
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            Logger.audioRecorder.error("Recording finished unsuccessfully")
        }
    }
}
