import XCTest
@testable import Typeleast

@MainActor
final class SoundManagerTests: XCTestCase {
    
    private var soundProvider: MockSoundProvider!
    private var soundManager: SoundManager!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!
    
    override func setUp() {
        super.setUp()
        defaultsSuiteName = "com.typeleast.tests.sound.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        soundProvider = MockSoundProvider()
        soundManager = SoundManager(soundProvider: soundProvider, userDefaults: defaults)
        defaults.removeObject(forKey: "playCompletionSound")
    }
    
    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        soundManager = nil
        soundProvider = nil
        defaults = nil
        defaultsSuiteName = nil
        super.tearDown()
    }
    
    func testPlayCompletionSound_DefaultPreferencePlaysGlass() {
        soundManager.playCompletionSound()
        
        XCTAssertEqual(soundProvider.requestedNames, ["Glass"])
        XCTAssertEqual(soundProvider.defaultSound.playCallCount, 1)
    }
    
    func testPlayCompletionSound_WhenDisabledDoesNotPlay() {
        defaults.set(false, forKey: "playCompletionSound")
        
        soundManager.playCompletionSound()
        
        XCTAssertTrue(soundProvider.requestedNames.isEmpty)
        XCTAssertEqual(soundProvider.defaultSound.playCallCount, 0)
    }
    
    func testPlayCompletionSound_WhenEnabledPlaysOnce() {
        defaults.set(true, forKey: "playCompletionSound")
        
        soundManager.playCompletionSound()
        
        XCTAssertEqual(soundProvider.requestedNames, ["Glass"])
        XCTAssertEqual(soundProvider.defaultSound.playCallCount, 1)
    }
    
    func testPlayRecordingStartSound_UsesPingSound() {
        soundManager.playRecordingStartSound()
        
        XCTAssertEqual(soundProvider.requestedNames, ["Ping"])
        XCTAssertEqual(soundProvider.defaultSound.playCallCount, 1)
    }
    
    func testPlayRecordingStartSound_WhenDisabledDoesNotPlay() {
        defaults.set(false, forKey: "playCompletionSound")
        
        soundManager.playRecordingStartSound()
        
        XCTAssertTrue(soundProvider.requestedNames.isEmpty)
        XCTAssertEqual(soundProvider.defaultSound.playCallCount, 0)
    }
}
