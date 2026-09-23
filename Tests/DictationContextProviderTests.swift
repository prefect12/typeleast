import XCTest
@testable import Typeleast

@MainActor
final class DictationContextProviderTests: XCTestCase {
    func testTermsComeFromEnglishMixedIntoChineseSentences() {
        let transcripts = [
            "这个campaign的数据怎么样",
            "帮我看一下 Campaign 的画像",
            "把这个 campaign 发到 Codex 里",
            "用 Codex 跑一下这个任务",
            "Can you do this in English only please",
            "Can we check it again in English",
            "这个 PR 只出现一次"
        ]

        let terms = DictationContextProvider.frequentMixedInTerms(in: transcripts)

        XCTAssertEqual(terms, ["campaign", "Codex"])
    }

    func testPromptIncludesTermsAndRecentSentencesWithinLimit() {
        let longSentence = String(repeating: "长", count: 400)
        let prompt = DictationContextProvider.prompt(
            terms: ["campaign", "Codex"],
            recentTranscripts: ["第一句", longSentence]
        )

        XCTAssertNotNil(prompt)
        XCTAssertTrue(prompt?.contains("说话人常用的词：campaign, Codex。") ?? false)
        XCTAssertTrue(prompt?.hasSuffix(String(repeating: "长", count: DictationContextProvider.recentCharacterLimit)) ?? false)
        XCTAssertFalse(prompt?.contains("第一句") ?? true)
        XCTAssertNil(DictationContextProvider.prompt(terms: [], recentTranscripts: []))
    }

    func testRefreshSeedsFromHistoryAndRecordTranscriptKeepsLatestSentences() async throws {
        let dataManager = MockDataManager()
        for text in ["更早的 campaign 记录", "campaign 第二条记录", "第三条", "最新一条"] {
            try await dataManager.saveTranscription(TranscriptionRecord(text: text, provider: .openAIRealtime))
            try await Task.sleep(for: .milliseconds(2))
        }
        let provider = DictationContextProvider()

        await provider.refreshIfNeeded(dataManager: dataManager)

        XCTAssertEqual(provider.terms, ["campaign"])
        XCTAssertEqual(provider.recentTranscripts.count, DictationContextProvider.recentTranscriptLimit)
        XCTAssertEqual(provider.recentTranscripts.last, "最新一条")

        provider.recordTranscript("  刚说的话  ")
        provider.recordTranscript("")
        XCTAssertEqual(provider.recentTranscripts.last, "刚说的话")
        XCTAssertEqual(provider.recentTranscripts.count, DictationContextProvider.recentTranscriptLimit)
    }
}
