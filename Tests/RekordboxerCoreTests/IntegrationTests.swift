import XCTest
@testable import RekordboxerCore

final class IntegrationTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testFullSyncWorkflow() throws {
        // 1. Create source folder structure
        let musicRoot = tempDir.appendingPathComponent("Music")
        let house = musicRoot.appendingPathComponent("House")
        let techno = musicRoot.appendingPathComponent("Techno")
        try FileManager.default.createDirectory(at: house, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: techno, withIntermediateDirectories: true)

        FileManager.default.createFile(atPath: house.appendingPathComponent("summer.mp3").path, contents: Data("mp3".utf8))
        FileManager.default.createFile(atPath: house.appendingPathComponent("vibes.wav").path, contents: Data("wav".utf8))
        FileManager.default.createFile(atPath: techno.appendingPathComponent("dark.flac").path, contents: Data("flac".utf8))

        // 2. Scan
        let folders = try FolderScanner.scan(root: musicRoot)
        XCTAssertEqual(folders.count, 2)

        // 3. Diff against empty library
        var library = RekordboxLibrary()
        var idMap = TrackIDMap()
        let diff = SyncEngine.diff(library: library, scannedFolders: folders)
        XCTAssertEqual(diff.newTracks.count, 3)

        // 4. Apply (no removals)
        SyncEngine.apply(diff: diff, to: &library, idMap: &idMap, removals: [])
        XCTAssertEqual(library.tracks.count, 3)
        XCTAssertEqual(library.rootNode.children.count, 2)

        // 5. Write XML
        let xmlData = try RekordboxXMLWriter.write(library: library)
        let xmlPath = tempDir.appendingPathComponent("rekordbox.xml")
        try xmlData.write(to: xmlPath)

        // 6. Re-read XML and verify
        let reloaded = try RekordboxXMLParser.parse(data: Data(contentsOf: xmlPath))
        XCTAssertEqual(reloaded.tracks.count, 3)

        let playlistNames = Set(reloaded.rootNode.children.map { $0.name })
        XCTAssertTrue(playlistNames.contains("House"))
        XCTAssertTrue(playlistNames.contains("Techno"))

        let anyTrack = reloaded.tracks.values.first { $0.name == "summer" }
        XCTAssertNotNil(anyTrack)
        XCTAssertTrue(anyTrack!.location.contains("summer.mp3"))

        // 7. Second scan — should detect no changes
        let diff2 = SyncEngine.diff(library: library, scannedFolders: folders)
        XCTAssertEqual(diff2.newTracks.count, 0)
        XCTAssertEqual(diff2.removedTracks.count, 0)
        XCTAssertEqual(diff2.unchangedCount, 3)

        // 8. Delete a file and scan — should detect removal
        try FileManager.default.removeItem(atPath: house.appendingPathComponent("summer.mp3").path)
        let folders3 = try FolderScanner.scan(root: musicRoot)
        let diff3 = SyncEngine.diff(library: library, scannedFolders: folders3)
        XCTAssertEqual(diff3.removedTracks.count, 1)
        XCTAssertEqual(diff3.removedTracks[0].name, "summer")
    }
}
