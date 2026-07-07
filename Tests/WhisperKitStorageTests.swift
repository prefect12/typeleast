import XCTest
@testable import Typeleast

final class WhisperKitStorageTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperKitStorageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        try super.tearDownWithError()
    }

    func testDownloadedModelDoesNotRequireTokenizerInCoreMLFolder() throws {
        let modelDirectory = try makeModelDirectory()

        XCTAssertTrue(WhisperKitStorage.isModelDownloaded(at: modelDirectory))
    }

    func testDownloadedModelRequiresTopLevelConfigFiles() throws {
        let modelDirectory = try makeModelDirectory()
        try FileManager.default.removeItem(at: modelDirectory.appendingPathComponent("generation_config.json"))

        XCTAssertFalse(WhisperKitStorage.isModelDownloaded(at: modelDirectory))
    }

    func testDownloadedModelRequiresCoreMLSentinels() throws {
        let modelDirectory = try makeModelDirectory()
        try FileManager.default.removeItem(
            at: modelDirectory
                .appendingPathComponent("TextDecoder.mlmodelc", isDirectory: true)
                .appendingPathComponent("coremldata.bin")
        )

        XCTAssertFalse(WhisperKitStorage.isModelDownloaded(at: modelDirectory))
    }

    private func makeModelDirectory() throws -> URL {
        let modelDirectory = temporaryDirectory.appendingPathComponent("openai_whisper-base", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("config.json"))
        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("generation_config.json"))

        for bundle in ["AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc", "TextDecoder.mlmodelc"] {
            let bundleDirectory = modelDirectory.appendingPathComponent(bundle, isDirectory: true)
            try FileManager.default.createDirectory(at: bundleDirectory, withIntermediateDirectories: true)
            try Data().write(to: bundleDirectory.appendingPathComponent("coremldata.bin"))
        }

        return modelDirectory
    }
}
