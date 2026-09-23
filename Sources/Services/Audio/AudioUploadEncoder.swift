import AVFoundation
import Foundation
import os.log

/// Shrinks uncompressed recordings before they are uploaded for batch transcription.
///
/// Realtime dictation records 24 kHz PCM16 WAV (48 KB/s). Encoding it to AAC cuts the upload
/// roughly 10x, which dominates batch latency on slow or proxied uplinks.
internal enum AudioUploadEncoder {
    static let bitRate = 32_000

    /// Returns a temporary AAC copy of a WAV file, or nil when the input is already compressed
    /// or cannot be encoded. The caller owns the returned file.
    static func compressedCopy(of url: URL) -> URL? {
        guard url.pathExtension.lowercased() == "wav" else { return nil }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)-\(UUID().uuidString).m4a")
        do {
            try encode(url, to: outputURL)
            return outputURL
        } catch {
            Logger.speechToText.error("Upload compression failed: \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: outputURL)
            return nil
        }
    }

    private static func encode(_ inputURL: URL, to outputURL: URL) throws {
        let input = try AVAudioFile(forReading: inputURL)
        let format = input.processingFormat
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderBitRateKey: bitRate
        ]
        // AVAudioFile finalizes the container when it is released at the end of this scope.
        let output = try AVAudioFile(
            forWriting: outputURL,
            settings: settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_384) else {
            throw SpeechToTextError.transcriptionFailed("Unable to allocate audio buffer")
        }
        while input.framePosition < input.length {
            try input.read(into: buffer)
            guard buffer.frameLength > 0 else { break }
            try output.write(from: buffer)
        }
    }
}
