import Foundation
import Observation

@Observable
@MainActor
internal final class TimingAnalysisStore {
    static let shared = TimingAnalysisStore()

    private(set) var records: [TranscriptionRecord] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var reloadToken = 0
    private var loadedLimit: Int?

    init() {}

    func loadIfNeeded(recordLimit: Int? = nil, dataManager: DataManagerProtocol = DataManager.shared) async {
        guard !hasLoaded || !loadedRecordsCover(recordLimit) else { return }
        await reload(recordLimit: recordLimit, dataManager: dataManager)
    }

    func reload(recordLimit: Int? = nil, dataManager: DataManagerProtocol = DataManager.shared) async {
        guard !isLoading else { return }

        isLoading = true
        let fetchedRecords: [TranscriptionRecord]
        do {
            fetchedRecords = try await dataManager.fetchRecords(matching: "", limit: recordLimit, offset: nil)
        } catch {
            fetchedRecords = await dataManager.fetchAllRecordsQuietly()
        }
        records = recordLimit.map { Array(fetchedRecords.prefix($0)) } ?? fetchedRecords
        loadedLimit = recordLimit
        hasLoaded = true
        isLoading = false
    }

    func invalidate() {
        hasLoaded = false
        loadedLimit = nil
        reloadToken += 1
    }

    func resetForTesting() {
        records = []
        isLoading = false
        hasLoaded = false
        loadedLimit = nil
        reloadToken = 0
    }

    private func loadedRecordsCover(_ requestedLimit: Int?) -> Bool {
        guard let loadedLimit else { return true }
        guard let requestedLimit else { return false }
        return loadedLimit >= requestedLimit
    }
}
