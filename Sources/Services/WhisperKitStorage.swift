import Foundation

internal enum WhisperKitStorage {
    // WhisperKit downloads CoreML bundles into a model folder. During download, the folder may exist with
    // partial contents (e.g. config JSON), so "is downloaded" must check the required CoreML bundles
    // rather than any single file extension. Tokenizers are managed separately by WhisperKit and may live
    // in a tokenizer repo cache instead of this CoreML model folder.
    private static let requiredCoreMLBundles = [
        "AudioEncoder.mlmodelc",
        "MelSpectrogram.mlmodelc",
        "TextDecoder.mlmodelc",
    ]

    private static func baseDirectory(fileManager: FileManager = .default) -> URL? {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml", isDirectory: true)
    }

    static func storageDirectory(fileManager: FileManager = .default) -> URL? {
        baseDirectory(fileManager: fileManager)
    }

    static func modelDirectory(for model: WhisperModel, fileManager: FileManager = .default) -> URL? {
        baseDirectory(fileManager: fileManager)?
            .appendingPathComponent(model.whisperKitModelName, isDirectory: true)
    }

    static func isModelDownloaded(_ model: WhisperModel, fileManager: FileManager = .default) -> Bool {
        guard let modelDirectory = modelDirectory(for: model, fileManager: fileManager) else { return false }
        return isModelDownloaded(at: modelDirectory, fileManager: fileManager)
    }

    static func isModelDownloaded(at modelDirectory: URL, fileManager: FileManager = .default) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: modelDirectory.path, isDirectory: &isDirectory)
        guard exists, isDirectory.boolValue else { return false }

        // Required top-level files
        let requiredFiles = ["config.json", "generation_config.json"]
        for file in requiredFiles {
            if !fileManager.fileExists(atPath: modelDirectory.appendingPathComponent(file).path) {
                return false
            }
        }

        // Required CoreML bundles (and a sentinel file inside each) to avoid partial-download false positives.
        for bundle in requiredCoreMLBundles {
            let bundleURL = modelDirectory.appendingPathComponent(bundle, isDirectory: true)
            var isBundleDir: ObjCBool = false
            guard fileManager.fileExists(atPath: bundleURL.path, isDirectory: &isBundleDir),
                  isBundleDir.boolValue else {
                return false
            }

            let sentinel = bundleURL.appendingPathComponent("coremldata.bin")
            if !fileManager.fileExists(atPath: sentinel.path) {
                return false
            }
        }

        return true
    }

    static func localModelPath(for model: WhisperModel, fileManager: FileManager = .default) -> String? {
        guard isModelDownloaded(model, fileManager: fileManager),
              let url = modelDirectory(for: model, fileManager: fileManager) else {
            return nil
        }
        return url.path
    }

    static func ensureBaseDirectoryExists(fileManager: FileManager = .default) {
        guard let baseDirectory = baseDirectory(fileManager: fileManager) else { return }
        try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }
}
