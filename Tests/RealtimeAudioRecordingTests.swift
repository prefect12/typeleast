import AVFoundation
import XCTest
@testable import Typeleast

final class RealtimeAudioRecordingTests: XCTestCase {
    func testPCMConverterProducesMonoPCM16Data() throws {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44_100,
            channels: 1,
            interleaved: false
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410))
        buffer.frameLength = 4_410
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for frame in 0..<Int(buffer.frameLength) {
            samples[frame] = sin(Float(frame) / 12.0) * 0.25
        }

        let pcmData = try XCTUnwrap(RealtimeAudioPCMConverter.pcm16Mono24kData(from: buffer))
        XCTAssertGreaterThan(pcmData.count, 0)
        XCTAssertEqual(pcmData.count % RealtimeAudioPCMConverter.bytesPerFrame, 0)
        XCTAssertLessThanOrEqual(abs(pcmData.count - 4_800), 500)
    }

    func testWAVWriterProducesValidAudioFile() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RealtimeAudioRecordingTests-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try PCM16WAVFileWriter(url: url)
        let frameCount = Int(RealtimeAudioPCMConverter.sampleRate / 10)
        try writer.append(Data(repeating: 0, count: frameCount * RealtimeAudioPCMConverter.bytesPerFrame))
        try writer.finish()

        let data = try Data(contentsOf: url)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: data.dropFirst(8).prefix(4), encoding: .ascii), "WAVE")
        XCTAssertEqual(data.count, 44 + frameCount * RealtimeAudioPCMConverter.bytesPerFrame)
        let validation = await AudioValidator.validateAudioFile(at: url)
        XCTAssertTrue(validation.isValid)
    }

    func testUploadEncoderCompressesRealtimeWAVAndKeepsDuration() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RealtimeAudioRecordingTests-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try PCM16WAVFileWriter(url: url)
        let frameCount = Int(RealtimeAudioPCMConverter.sampleRate) * 5
        var samples = [Int16](repeating: 0, count: frameCount)
        for frame in 0..<frameCount {
            samples[frame] = Int16(8_000 * sin(Double(frame) * 2 * .pi * 220 / RealtimeAudioPCMConverter.sampleRate))
        }
        try writer.append(samples.withUnsafeBufferPointer { Data(buffer: $0) })
        try writer.finish()

        let compressedURL = try XCTUnwrap(AudioUploadEncoder.compressedCopy(of: url))
        defer { try? FileManager.default.removeItem(at: compressedURL) }

        XCTAssertEqual(compressedURL.pathExtension, "m4a")
        let wavSize = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
        let compressedSize = try XCTUnwrap(
            try FileManager.default.attributesOfItem(atPath: compressedURL.path)[.size] as? Int
        )
        XCTAssertLessThan(compressedSize * 5, wavSize)

        let compressed = try AVAudioFile(forReading: compressedURL)
        let seconds = Double(compressed.length) / compressed.fileFormat.sampleRate
        XCTAssertEqual(seconds, 5, accuracy: 0.1)
        let validation = await AudioValidator.validateAudioFile(at: compressedURL)
        XCTAssertTrue(validation.isValid)
    }

    func testUploadEncoderLeavesCompressedAndInvalidFilesAlone() throws {
        let m4aURL = FileManager.default.temporaryDirectory.appendingPathComponent("already-compressed.m4a")
        XCTAssertNil(AudioUploadEncoder.compressedCopy(of: m4aURL))

        let brokenURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RealtimeAudioRecordingTests-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: brokenURL) }
        try Data([0x00, 0x01, 0x02]).write(to: brokenURL)
        XCTAssertNil(AudioUploadEncoder.compressedCopy(of: brokenURL))
    }
}
