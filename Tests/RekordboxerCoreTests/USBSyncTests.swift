import XCTest
@testable import RekordboxerCore

final class USBSyncTests: XCTestCase {
    var sourceDir: URL!
    var usbDir: URL!

    override func setUp() {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        sourceDir = base.appendingPathComponent("source")
        usbDir = base.appendingPathComponent("usb")
        try! FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: usbDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: sourceDir.deletingLastPathComponent())
    }

    func testDetectsNewFiles() throws {
        FileManager.default.createFile(atPath: sourceDir.appendingPathComponent("new.mp3").path, contents: Data("audio".utf8))

        let tracks = [makeTrack(path: sourceDir.appendingPathComponent("new.mp3").path)]
        let plan = try USBSync.plan(tracks: tracks, usbRoot: usbDir, manifest: USBManifest())

        XCTAssertEqual(plan.filesToCopy.count, 1)
        XCTAssertEqual(plan.filesToCopy[0].source.lastPathComponent, "new.mp3")
    }

    func testSkipsUnchangedFiles() throws {
        let data = Data("audio".utf8)
        let sourcePath = sourceDir.appendingPathComponent("existing.mp3")
        let usbPath = usbDir.appendingPathComponent("existing.mp3")
        FileManager.default.createFile(atPath: sourcePath.path, contents: data)
        FileManager.default.createFile(atPath: usbPath.path, contents: data)

        let tracks = [makeTrack(path: sourcePath.path)]
        var manifest = USBManifest()
        let attrs = try FileManager.default.attributesOfItem(atPath: sourcePath.path)
        let modDate = attrs[.modificationDate] as! Date
        manifest.entries["existing.mp3"] = USBManifestEntry(size: Int64(data.count), modificationDate: modDate)

        let plan = try USBSync.plan(tracks: tracks, usbRoot: usbDir, manifest: manifest)
        XCTAssertEqual(plan.filesToCopy.count, 0)
    }

    func testDetectsChangedFiles() throws {
        let sourcePath = sourceDir.appendingPathComponent("changed.mp3")
        let usbPath = usbDir.appendingPathComponent("changed.mp3")
        FileManager.default.createFile(atPath: sourcePath.path, contents: Data("new audio data".utf8))
        FileManager.default.createFile(atPath: usbPath.path, contents: Data("old".utf8))

        let tracks = [makeTrack(path: sourcePath.path)]
        var manifest = USBManifest()
        manifest.entries["changed.mp3"] = USBManifestEntry(size: 3, modificationDate: Date.distantPast)

        let plan = try USBSync.plan(tracks: tracks, usbRoot: usbDir, manifest: manifest)
        XCTAssertEqual(plan.filesToCopy.count, 1)
    }

    func testExecuteCopiesFiles() throws {
        let data = Data("audio content".utf8)
        let sourcePath = sourceDir.appendingPathComponent("copy_me.mp3")
        FileManager.default.createFile(atPath: sourcePath.path, contents: data)

        let tracks = [makeTrack(path: sourcePath.path)]
        let plan = try USBSync.plan(tracks: tracks, usbRoot: usbDir, manifest: USBManifest())
        let manifest = try USBSync.execute(plan: plan)

        let usbFile = usbDir.appendingPathComponent("copy_me.mp3")
        XCTAssertTrue(FileManager.default.fileExists(atPath: usbFile.path))
        XCTAssertEqual(try Data(contentsOf: usbFile), data)
        XCTAssertNotNil(manifest.entries["copy_me.mp3"])
    }

    func testSelectivePlaylistSync() throws {
        let data = Data("audio".utf8)
        FileManager.default.createFile(atPath: sourceDir.appendingPathComponent("house.mp3").path, contents: data)
        FileManager.default.createFile(atPath: sourceDir.appendingPathComponent("techno.mp3").path, contents: data)

        let tracks = [makeTrack(path: sourceDir.appendingPathComponent("house.mp3").path)]
        let plan = try USBSync.plan(tracks: tracks, usbRoot: usbDir, manifest: USBManifest())

        XCTAssertEqual(plan.filesToCopy.count, 1)
        XCTAssertEqual(plan.filesToCopy[0].source.lastPathComponent, "house.mp3")
    }

    private func makeTrack(path: String) -> Track {
        var track = Track(trackID: 1)
        track.location = Track.encodeLocation(path)
        return track
    }
}
