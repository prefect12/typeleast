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

    init() {}

    func loadIfNeeded(dataManager: DataManagerProtocol = DataManager.shared) async {
        guard !hasLoaded else { return }
        await reload(dataManager: dataManager)
    }

    func reload(dataManager: DataManagerProtocol = DataManager.shared) async {
        guard !isLoading else { return }

        isLoading = true
        let fetchedRecords = await dataManager.fetchAllRecordsQuietly()
        records = fetchedRecords
        hasLoaded = true
        isLoading = false
    }

    func invalidate() {
        hasLoaded = false
        reloadToken += 1
    }

    func resetForTesting() {
        records = []
        isLoading = false
        hasLoaded = false
        reloadToken = 0
    }
}
