import Foundation

internal final class PCM16WAVFileWriter: @unchecked Sendable {
    private let url: URL
    private let sampleRate: UInt32
    private let channelCount: UInt16
    private let bitsPerSample: UInt16
    private let fileHandle: FileHandle
    private let lock = NSLock()
    private var dataByteCount: UInt32 = 0
    private var isClosed = false

    init(
        url: URL,
        sampleRate: UInt32 = UInt32(RealtimeAudioPCMConverter.sampleRate),
        channelCount: UInt16 = UInt16(RealtimeAudioPCMConverter.channelCount),
        bitsPerSample: UInt16 = 16
    ) throws {
        self.url = url
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bitsPerSample = bitsPerSample
        FileManager.default.createFile(atPath: url.path, contents: nil)
        fileHandle = try FileHandle(forWritingTo: url)
        try fileHandle.write(contentsOf: Self.header(
            dataByteCount: 0,
            sampleRate: sampleRate,
            channelCount: channelCount,
            bitsPerSample: bitsPerSample
        ))
    }

    func append(_ data: Data) throws {
        guard !data.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else { return }
        try fileHandle.write(contentsOf: data)
        dataByteCount = dataByteCount.addingReportingOverflow(UInt32(data.count)).partialValue
    }

    func finish() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else { return }
        try fileHandle.seek(toOffset: 0)
        try fileHandle.write(contentsOf: Self.header(
            dataByteCount: dataByteCount,
            sampleRate: sampleRate,
            channelCount: channelCount,
            bitsPerSample: bitsPerSample
        ))
        try fileHandle.close()
        isClosed = true
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else { return }
        try? fileHandle.close()
        isClosed = true
        try? FileManager.default.removeItem(at: url)
    }

    private static func header(
        dataByteCount: UInt32,
        sampleRate: UInt32,
        channelCount: UInt16,
        bitsPerSample: UInt16
    ) -> Data {
        var data = Data()
        let byteRate = sampleRate * UInt32(channelCount) * UInt32(bitsPerSample / 8)
        let blockAlign = channelCount * (bitsPerSample / 8)
        data.appendASCII("RIFF")
        data.appendLittleEndian(36 &+ dataByteCount)
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(channelCount)
        data.appendLittleEndian(sampleRate)
        data.appendLittleEndian(byteRate)
        data.appendLittleEndian(blockAlign)
        data.appendLittleEndian(bitsPerSample)
        data.appendASCII("data")
        data.appendLittleEndian(dataByteCount)
        return data
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) { append(contentsOf: string.utf8) }

    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { buffer in
            append(buffer.bindMemory(to: UInt8.self))
        }
    }
}
