import XCTest
@testable import RekordboxerCore

final class USBSyncTests: XCTestCase {
    var sourceDir: URL!
    var usbDir: URL!
    var contentsDir: URL!

    override func setUp() {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        sourceDir = base.appendingPathComponent("source")
        usbDir = base.appendingPathComponent("usb")
        contentsDir = usbDir.appendingPathComponent("Contents")
        try! FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        // Simulate rekordbox USB structure: Contents/Artist/Album/
        try! FileManager.default.createDirectory(at: contentsDir.appendingPathComponent("Artist/Album"), withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: sourceDir.deletingLastPathComponent())
    }

    func testSkipsFilesNotOnUSB() throws {
        // Source has a file but USB doesn't — should be skipped (not our job to add new files)
        FileManager.default.createFile(atPath: sourceDir.appendingPathComponent("new.mp3").path, contents: Data("audio".utf8))

        let tracks = [makeTrack(path: sourceDir.appendingPathComponent("new.mp3").path)]
        let plan = try USBSync.plan(tracks: tracks, usbRoot: usbDir)

        XCTAssertEqual(plan.filesToCopy.count, 0)
    }

    func testSkipsUnchangedFiles() throws {
        let data = Data("audio".utf8)
        let sourcePath = sourceDir.appendingPathComponent("existing.mp3")
        let usbPath = contentsDir.appendingPathComponent("Artist/Album/existing.mp3")
        FileManager.default.createFile(atPath: sourcePath.path, contents: data)
        FileManager.default.createFile(atPath: usbPath.path, contents: data)

        let tracks = [makeTrack(path: sourcePath.path)]
        let plan = try USBSync.plan(tracks: tracks, usbRoot: usbDir)
        XCTAssertEqual(plan.filesToCopy.count, 0)
    }

    func testDetectsChangedFiles() throws {
        let sourcePath = sourceDir.appendingPathComponent("changed.mp3")
        let usbPath = contentsDir.appendingPathComponent("Artist/Album/changed.mp3")
        FileManager.default.createFile(atPath: sourcePath.path, contents: Data("new audio data".utf8))
        FileManager.default.createFile(atPath: usbPath.path, contents: Data("old".utf8))

        let tracks = [makeTrack(path: sourcePath.path)]
        let plan = try USBSync.plan(tracks: tracks, usbRoot: usbDir)
        XCTAssertEqual(plan.filesToCopy.count, 1)
        // Should target the existing location on USB, not the root
        XCTAssertTrue(plan.filesToCopy[0].destination.path.hasSuffix("Contents/Artist/Album/changed.mp3"))
    }

    func testExecuteOverwritesInPlace() throws {
        let oldData = Data("old audio".utf8)
        let newData = Data("new audio content".utf8)
        let sourcePath = sourceDir.appendingPathComponent("update_me.mp3")
        let usbPath = contentsDir.appendingPathComponent("Artist/Album/update_me.mp3")
        FileManager.default.createFile(atPath: sourcePath.path, contents: newData)
        FileManager.default.createFile(atPath: usbPath.path, contents: oldData)

        let tracks = [makeTrack(path: sourcePath.path)]
        let plan = try USBSync.plan(tracks: tracks, usbRoot: usbDir)
        try USBSync.execute(plan: plan)

        // File should be updated in its original rekordbox location
        XCTAssertTrue(FileManager.default.fileExists(atPath: usbPath.path))
        XCTAssertEqual(try Data(contentsOf: usbPath), newData)
    }

    func testSelectivePlaylistSync() throws {
        let data = Data("audio".utf8)
        FileManager.default.createFile(atPath: sourceDir.appendingPathComponent("house.mp3").path, contents: data)
        FileManager.default.createFile(atPath: sourceDir.appendingPathComponent("techno.mp3").path, contents: data)
        // Only house.mp3 exists on USB
        FileManager.default.createFile(atPath: contentsDir.appendingPathComponent("Artist/Album/house.mp3").path, contents: Data("old".utf8))

        let tracks = [makeTrack(path: sourceDir.appendingPathComponent("house.mp3").path)]
        let plan = try USBSync.plan(tracks: tracks, usbRoot: usbDir)

        XCTAssertEqual(plan.filesToCopy.count, 1)
        XCTAssertEqual(plan.filesToCopy[0].source.lastPathComponent, "house.mp3")
    }

    private func makeTrack(path: String) -> Track {
        var track = Track(trackID: 1)
        track.location = Track.encodeLocation(path)
        return track
    }
}
