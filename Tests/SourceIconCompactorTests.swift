import AppKit
import SwiftData
import XCTest
@testable import Typeleast

final class SourceIconCompactorTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SourceIconCompactorTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testCompactsOversizedIconsOnceAndLeavesSmallOnesAlone() async throws {
        let container = try ModelContainer(
            for: TranscriptionRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let largeIcon = try XCTUnwrap(Self.noisyPNG(side: 512))
        XCTAssertGreaterThan(largeIcon.count, SourceIconCompactor.oversizedIconBytes)
        let smallIcon = try XCTUnwrap(SourceAppInfo.pngData(from: NSImage(data: largeIcon)))

        let context = ModelContext(container)
        for index in 0..<7 {
            context.insert(TranscriptionRecord(
                text: "record \(index)",
                provider: .openAIRealtime,
                sourceAppBundleId: "com.example.editor",
                sourceAppIconData: index == 6 ? smallIcon : largeIcon
            ))
        }
        context.insert(TranscriptionRecord(text: "no icon", provider: .openAIRealtime))
        try context.save()

        let compacted = await SourceIconCompactor.compactIfNeeded(container: container, defaults: defaults)

        XCTAssertEqual(compacted, 6)
        XCTAssertTrue(defaults.bool(forKey: SourceIconCompactor.completedDefaultsKey))
        let records = try ModelContext(container).fetch(FetchDescriptor<TranscriptionRecord>())
        XCTAssertEqual(records.count, 8)
        for record in records where record.sourceAppIconData != nil {
            let data = try XCTUnwrap(record.sourceAppIconData)
            XCTAssertLessThanOrEqual(data.count, SourceIconCompactor.oversizedIconBytes)
            XCTAssertEqual(NSBitmapImageRep(data: data)?.pixelsWide, SourceAppInfo.iconPixelSize)
        }
        XCTAssertEqual(records.filter { $0.sourceAppIconData == nil }.count, 1)

        let secondRun = await SourceIconCompactor.compactIfNeeded(container: container, defaults: defaults)
        XCTAssertEqual(secondRun, 0)
    }

    /// Random pixels defeat PNG compression, standing in for a detailed full-size app icon.
    private static func noisyPNG(side: Int) -> Data? {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let pixels = bitmap.bitmapData else { return nil }
        for offset in 0..<(bitmap.bytesPerRow * side) {
            pixels[offset] = UInt8.random(in: 0...255)
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
