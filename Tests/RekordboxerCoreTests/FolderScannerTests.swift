import XCTest
@testable import RekordboxerCore

final class FolderScannerTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let house = tempDir.appendingPathComponent("House")
        let techno = tempDir.appendingPathComponent("Techno")
        try! FileManager.default.createDirectory(at: house, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: techno, withIntermediateDirectories: true)

        FileManager.default.createFile(atPath: house.appendingPathComponent("track1.mp3").path, contents: Data("audio".utf8))
        FileManager.default.createFile(atPath: house.appendingPathComponent("track2.wav").path, contents: Data("audio".utf8))
        FileManager.default.createFile(atPath: techno.appendingPathComponent("track3.flac").path, contents: Data("audio".utf8))
        FileManager.default.createFile(atPath: tempDir.appendingPathComponent("readme.txt").path, contents: Data("text".utf8))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testScanFindsAudioFiles() throws {
        let result = try FolderScanner.scan(root: tempDir)
        let allFiles = result.flatMap { $0.files }
        XCTAssertEqual(allFiles.count, 3)
    }

    func testScanIgnoresNonAudioFiles() throws {
        let result = try FolderScanner.scan(root: tempDir)
        let allFiles = result.flatMap { $0.files }
        XCTAssertFalse(allFiles.contains { $0.url.lastPathComponent == "readme.txt" })
    }

    func testScanGroupsByFolder() throws {
        let result = try FolderScanner.scan(root: tempDir)
        XCTAssertEqual(result.count, 2)

        let names = Set(result.map { $0.folderName })
        XCTAssertTrue(names.contains("House"))
        XCTAssertTrue(names.contains("Techno"))
    }

    func testScanCapturesFileMetadata() throws {
        let result = try FolderScanner.scan(root: tempDir)
        let house = result.first { $0.folderName == "House" }!
        let file = house.files.first { $0.url.lastPathComponent == "track1.mp3" }!
        XCTAssertGreaterThan(file.size, 0)
        XCTAssertNotNil(file.modificationDate)
    }

    func testScanFindsNestedFiles() throws {
        // Add nested subfolder: House/Deep/track4.mp3
        let deep = tempDir.appendingPathComponent("House/Deep")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: deep.appendingPathComponent("track4.mp3").path, contents: Data("audio".utf8))

        let result = try FolderScanner.scan(root: tempDir)
        let house = result.first { $0.folderName == "House" }!
        // Direct files: track1, track2. Nested in Deep/: track4
        XCTAssertEqual(house.files.count, 2)
        XCTAssertEqual(house.children.count, 1)
        XCTAssertEqual(house.children[0].folderName, "Deep")
        XCTAssertEqual(house.allFiles.count, 3)
        XCTAssertTrue(house.allFiles.contains { $0.url.lastPathComponent == "track4.mp3" })
    }

    func testScanFindsRootLevelAudioFiles() throws {
        // Add audio file directly in root
        FileManager.default.createFile(atPath: tempDir.appendingPathComponent("loose.mp3").path, contents: Data("audio".utf8))

        let result = try FolderScanner.scan(root: tempDir)
        let allFiles = result.flatMap { $0.files }
        XCTAssertTrue(allFiles.contains { $0.url.lastPathComponent == "loose.mp3" })
    }
}
