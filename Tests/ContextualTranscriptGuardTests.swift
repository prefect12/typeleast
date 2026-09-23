import XCTest
@testable import Typeleast

final class ContextualTranscriptGuardTests: XCTestCase {
    private let recent = ["这个campaign数据到底怎么样?", "跑完之后把最后结果给我"]

    func testSilentShortRecordingThatProducedASentenceIsRejected() {
        // The real case: 0.6s of silence came back as a sentence from the prompt.
        XCTAssertEqual(
            ContextualTranscriptGuard.rejection(for: "这个campaign数据怎么样?", audioSeconds: 0.6, recentTranscripts: []),
            .tooLongForAudio
        )
    }

    func testTranscriptRepeatingRecentSpeechIsRejectedEvenWhenLongEnough() {
        XCTAssertEqual(
            ContextualTranscriptGuard.rejection(for: "这个campaign数据怎么样?", audioSeconds: 3, recentTranscripts: recent),
            .echoesRecentSpeech
        )
        XCTAssertEqual(
            ContextualTranscriptGuard.rejection(for: "跑完之后", audioSeconds: 2, recentTranscripts: recent),
            .echoesRecentSpeech
        )
    }

    func testNewSpeechAtNormalPaceIsKept() {
        XCTAssertNil(ContextualTranscriptGuard.rejection(
            for: "我没有说话,为什么他还是返回了左边这段话,怎么回事?",
            audioSeconds: 6.2,
            recentTranscripts: recent
        ))
        XCTAssertNil(ContextualTranscriptGuard.rejection(for: "好的", audioSeconds: 0.5, recentTranscripts: ["好的"]))
        XCTAssertNil(ContextualTranscriptGuard.rejection(for: "", audioSeconds: 0.5, recentTranscripts: recent))
    }

    func testSpokenUnitsCountHanCharactersAndLatinWords() {
        XCTAssertEqual(ContextualTranscriptGuard.spokenUnitCount("这个campaign数据 2332 OK?"), 7)
    }

    func testSimilarityIsNormalizedEditDistance() {
        XCTAssertEqual(ContextualTranscriptGuard.similarity(Array("abcd"), Array("abcd")), 1)
        XCTAssertEqual(ContextualTranscriptGuard.similarity(Array("abcd"), Array("abce")), 0.75, accuracy: 0.001)
        XCTAssertEqual(ContextualTranscriptGuard.similarity(Array(""), Array("abc")), 0)
    }
}
