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
}
