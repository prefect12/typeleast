@preconcurrency import AVFoundation
import Foundation

internal enum RealtimeAudioPCMConverter {
    static let sampleRate: Double = 24_000
    static let channelCount: AVAudioChannelCount = 1
    static let bytesPerFrame = 2

    nonisolated static func pcm16Mono24kData(from buffer: AVAudioPCMBuffer) -> Data? {
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        ), let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else {
            return nil
        }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else {
            return nil
        }

        var didProvideInput = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, outputBuffer.frameLength > 0,
              let channelData = outputBuffer.int16ChannelData else {
            return nil
        }
        return Data(
            bytes: channelData[0],
            count: Int(outputBuffer.frameLength) * bytesPerFrame
        )
    }
}
