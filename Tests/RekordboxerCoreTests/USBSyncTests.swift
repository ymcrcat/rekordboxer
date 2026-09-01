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

    func testFallbackToUsbRootWhenNoContentsDir() throws {
        // When USB has no Contents/ subdirectory (non-rekordbox layout), plan() should
        // search from usbRoot directly rather than crashing or returning empty results.
        let flatUSB = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: flatUSB, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: flatUSB) }

        let sourcePath = sourceDir.appendingPathComponent("flat.mp3")
        FileManager.default.createFile(atPath: sourcePath.path, contents: Data("new audio".utf8))
        FileManager.default.createFile(atPath: flatUSB.appendingPathComponent("flat.mp3").path, contents: Data("old".utf8))

        let tracks = [makeTrack(path: sourcePath.path)]
        let plan = try USBSync.plan(tracks: tracks, usbRoot: flatUSB)

        XCTAssertEqual(plan.filesToCopy.count, 1)
        XCTAssertEqual(plan.filesToCopy[0].destination.lastPathComponent, "flat.mp3")
    }

    func testDuplicateUSBFilesAreAmbiguous() throws {
        // Two same-named files on the USB — copying could overwrite the wrong one
        let otherAlbum = contentsDir.appendingPathComponent("Artist/Other")
        try FileManager.default.createDirectory(at: otherAlbum, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: sourceDir.appendingPathComponent("dup.mp3").path, contents: Data("newer".utf8))
        FileManager.default.createFile(atPath: contentsDir.appendingPathComponent("Artist/Album/dup.mp3").path, contents: Data("a".utf8))
        FileManager.default.createFile(atPath: otherAlbum.appendingPathComponent("dup.mp3").path, contents: Data("b".utf8))

        let plan = try USBSync.plan(tracks: [makeTrack(path: sourceDir.appendingPathComponent("dup.mp3").path)], usbRoot: usbDir)

        XCTAssertEqual(plan.filesToCopy.count, 0)
        XCTAssertEqual(plan.skippedAmbiguous, ["dup.mp3"])
    }

    func testSameSizeOlderSourceStillCopied() throws {
        // abs() direction: a USB mtime ahead of the source (FAT timezone shift)
        // must read as "differs — recopy", never "skip an edited file"
        let data = Data("12345".utf8)
        let sourcePath = sourceDir.appendingPathComponent("shifted.mp3")
        let usbPath = contentsDir.appendingPathComponent("Artist/Album/shifted.mp3")
        FileManager.default.createFile(atPath: sourcePath.path, contents: data)
        FileManager.default.createFile(atPath: usbPath.path, contents: data)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: 3600)],
            ofItemAtPath: usbPath.path
        )

        let plan = try USBSync.plan(tracks: [makeTrack(path: sourcePath.path)], usbRoot: usbDir)
        XCTAssertEqual(plan.filesToCopy.count, 1)
    }

    func testUnicodeFilenamesMatchAcrossNormalization() throws {
        // Source path precomposed (NFC), USB file decomposed (NFD) — must match
        let precomposed = "Caf\u{00E9}.mp3"
        let decomposed = "Caf\u{0065}\u{0301}.mp3"
        let sourcePath = sourceDir.appendingPathComponent(precomposed)
        let usbPath = contentsDir.appendingPathComponent("Artist/Album/\(decomposed)")
        FileManager.default.createFile(atPath: sourcePath.path, contents: Data("new audio".utf8))
        FileManager.default.createFile(atPath: usbPath.path, contents: Data("old".utf8))

        let plan = try USBSync.plan(tracks: [makeTrack(path: sourcePath.path)], usbRoot: usbDir)
        XCTAssertEqual(plan.filesToCopy.count, 1)
        XCTAssertEqual(plan.filesToCopy[0].filename, precomposed)
    }

    func testSameSizeNewerSourceIsCopied() throws {
        // Same byte size but source modified later — must still sync
        let data = Data("12345".utf8)
        let sourcePath = sourceDir.appendingPathComponent("same.mp3")
        let usbPath = contentsDir.appendingPathComponent("Artist/Album/same.mp3")
        FileManager.default.createFile(atPath: sourcePath.path, contents: data)
        FileManager.default.createFile(atPath: usbPath.path, contents: data)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -3600)],
            ofItemAtPath: usbPath.path
        )

        let plan = try USBSync.plan(tracks: [makeTrack(path: sourcePath.path)], usbRoot: usbDir)
        XCTAssertEqual(plan.filesToCopy.count, 1)
    }

    func testDuplicateSourceFilenamesAreAmbiguous() throws {
        // Two different source tracks named the same would both overwrite the
        // single matching USB file — must be skipped as ambiguous
        let dirA = sourceDir.appendingPathComponent("A")
        let dirB = sourceDir.appendingPathComponent("B")
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: dirA.appendingPathComponent("dup.mp3").path, contents: Data("aaa".utf8))
        FileManager.default.createFile(atPath: dirB.appendingPathComponent("dup.mp3").path, contents: Data("bbbbb".utf8))
        FileManager.default.createFile(atPath: contentsDir.appendingPathComponent("Artist/Album/dup.mp3").path, contents: Data("old".utf8))

        let tracks = [
            makeTrack(path: dirA.appendingPathComponent("dup.mp3").path),
            makeTrack(path: dirB.appendingPathComponent("dup.mp3").path),
        ]
        let plan = try USBSync.plan(tracks: tracks, usbRoot: usbDir)

        XCTAssertEqual(plan.filesToCopy.count, 0)
        XCTAssertEqual(plan.skippedAmbiguous, ["dup.mp3"])
    }

    func testAmbiguityConsidersWholeLibrary() throws {
        // Only one dup.mp3 is selected, but another library track shares the
        // filename — copying would overwrite the unrelated file on the USB
        let dirA = sourceDir.appendingPathComponent("A")
        let dirB = sourceDir.appendingPathComponent("B")
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: dirA.appendingPathComponent("dup.mp3").path, contents: Data("aaa".utf8))
        FileManager.default.createFile(atPath: dirB.appendingPathComponent("dup.mp3").path, contents: Data("bbbbb".utf8))
        FileManager.default.createFile(atPath: contentsDir.appendingPathComponent("Artist/Album/dup.mp3").path, contents: Data("old".utf8))

        let selected = makeTrack(path: dirA.appendingPathComponent("dup.mp3").path)
        let unselected = makeTrack(path: dirB.appendingPathComponent("dup.mp3").path)
        let plan = try USBSync.plan(tracks: [selected], allTracks: [selected, unselected], usbRoot: usbDir)

        XCTAssertEqual(plan.filesToCopy.count, 0)
        XCTAssertEqual(plan.skippedAmbiguous, ["dup.mp3"])
    }

    func testPlanReportsMissingFiles() throws {
        // Not on USB
        FileManager.default.createFile(atPath: sourceDir.appendingPathComponent("new.mp3").path, contents: Data("audio".utf8))
        // Source missing entirely
        let tracks = [
            makeTrack(path: sourceDir.appendingPathComponent("new.mp3").path),
            makeTrack(path: sourceDir.appendingPathComponent("gone.mp3").path),
        ]
        let plan = try USBSync.plan(tracks: tracks, usbRoot: usbDir)

        XCTAssertEqual(plan.filesToCopy.count, 0)
        XCTAssertEqual(plan.notOnUSB, ["new.mp3"])
        XCTAssertEqual(plan.sourceMissing, ["gone.mp3"])
    }

    func testExecuteCleansUpTempOnFailure() throws {
        // Destination exists but source vanishes before execute: destination
        // must survive and no temp file may be left behind
        let usbPath = contentsDir.appendingPathComponent("Artist/Album/keep.mp3")
        FileManager.default.createFile(atPath: usbPath.path, contents: Data("precious".utf8))

        let missingSource = sourceDir.appendingPathComponent("vanished.mp3")
        let plan = USBSyncPlan(
            filesToCopy: [.init(source: missingSource, destination: usbPath, filename: "keep.mp3")],
            usbRoot: usbDir
        )

        XCTAssertThrowsError(try USBSync.execute(plan: plan))
        XCTAssertEqual(try Data(contentsOf: usbPath), Data("precious".utf8))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: usbPath.deletingLastPathComponent().path)
            .filter { $0.hasPrefix(".rekordboxer-tmp-") }
        XCTAssertEqual(leftovers, [])
    }

    private func makeTrack(path: String) -> Track {
        var track = Track(trackID: 1)
        track.location = Track.encodeLocation(path)
        return track
    }
}
