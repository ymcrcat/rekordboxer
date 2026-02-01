import XCTest
@testable import RekordboxerCore

final class AppStateTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testSettingsRoundTrip() throws {
        let settingsURL = tempDir.appendingPathComponent("settings.json")
        var settings = AppSettings()
        settings.sourceFolderPath = "/Users/dj/Dropbox/Music"
        settings.xmlFilePath = "/Users/dj/rekordbox.xml"

        try settings.save(to: settingsURL)
        let loaded = try AppSettings.load(from: settingsURL)

        XCTAssertEqual(loaded.sourceFolderPath, "/Users/dj/Dropbox/Music")
        XCTAssertEqual(loaded.xmlFilePath, "/Users/dj/rekordbox.xml")
    }

    func testTrackIDMapRoundTrip() throws {
        let mapURL = tempDir.appendingPathComponent("trackids.json")
        var idMap = TrackIDMap()
        let id1 = idMap.getOrAssign(path: "/music/track1.mp3")
        let id2 = idMap.getOrAssign(path: "/music/track2.mp3")

        try idMap.save(to: mapURL)
        var loaded = try TrackIDMap.load(from: mapURL)

        XCTAssertEqual(loaded.getOrAssign(path: "/music/track1.mp3"), id1)
        XCTAssertEqual(loaded.getOrAssign(path: "/music/track2.mp3"), id2)
    }
}
