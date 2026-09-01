import XCTest
@testable import RekordboxerCore

final class LibraryBackupTests: XCTestCase {
    var dir: URL!
    var xmlPath: String!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        xmlPath = dir.appendingPathComponent("rekordbox.xml").path
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func writeXML(_ contents: String) {
        FileManager.default.createFile(atPath: xmlPath, contents: Data(contents.utf8))
    }

    private func backupNames() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?
            .filter { $0.hasSuffix(".bak") }.sorted() ?? []
    }

    // MARK: - backup

    func testBackupCopiesExistingContentAside() throws {
        writeXML("<ORIGINAL/>")
        let backup = try LibraryBackup.backup(xmlPath: xmlPath)

        XCTAssertNotNil(backup)
        XCTAssertEqual(try String(contentsOf: backup!, encoding: .utf8), "<ORIGINAL/>")
        // Original is untouched by the backup itself
        XCTAssertEqual(try String(contentsOfFile: xmlPath, encoding: .utf8), "<ORIGINAL/>")
    }

    func testBackupIsNoOpWhenNoFileExists() throws {
        let backup = try LibraryBackup.backup(xmlPath: xmlPath)
        XCTAssertNil(backup)
        XCTAssertEqual(backupNames(), [])
    }

    func testBackupSurvivesTwoSyncsInTheSameSecond() throws {
        // One-second filename granularity must not make the second sync throw
        writeXML("<FIRST/>")
        let now = Date()
        let a = try LibraryBackup.backup(xmlPath: xmlPath, now: now)
        writeXML("<SECOND/>")
        let b = try LibraryBackup.backup(xmlPath: xmlPath, now: now)

        XCTAssertNotEqual(a!.path, b!.path)
        XCTAssertEqual(try String(contentsOf: a!, encoding: .utf8), "<FIRST/>")
        XCTAssertEqual(try String(contentsOf: b!, encoding: .utf8), "<SECOND/>")
    }

    // MARK: - prune

    func testPruneKeepsNewestFiveAndDropsOlder() throws {
        writeXML("<X/>")
        // Seven backups at distinct timestamps, one minute apart
        let dates = (0..<7).map { Date(timeIntervalSince1970: 1_700_000_000 + Double($0 * 60)) }
        for d in dates {
            _ = try LibraryBackup.backup(xmlPath: xmlPath, now: d)
        }

        let expected = dates.suffix(5)
            .map { "rekordbox.xml.\(LibraryBackup.formatter.string(from: $0)).bak" }
            .sorted()
        XCTAssertEqual(backupNames(), expected, "the newest five backups must survive")
    }

    func testPruneLeavesUserBackupsAlone() throws {
        writeXML("<X/>")
        let handmade = dir.appendingPathComponent("rekordbox.xml.before-gig.bak")
        FileManager.default.createFile(atPath: handmade.path, contents: Data("mine".utf8))

        for i in 0..<8 {
            _ = try LibraryBackup.backup(xmlPath: xmlPath, now: Date(timeIntervalSince1970: 1_700_000_000 + Double(i * 60)))
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: handmade.path),
                      "a hand-made .bak must never be pruned")
    }

    // MARK: - staleness

    func testStalenessAllowsUnchangedFile() {
        let d = Date()
        XCTAssertNil(LibraryBackup.staleness(loaded: d, current: d))
    }

    func testStalenessBlocksAnyMtimeDifference() {
        let loaded = Date(timeIntervalSince1970: 1_000)
        // Newer (rekordbox wrote) and older (restored from backup) both block
        XCTAssertEqual(LibraryBackup.staleness(loaded: loaded, current: Date(timeIntervalSince1970: 2_000)), .changedOnDisk)
        XCTAssertEqual(LibraryBackup.staleness(loaded: loaded, current: Date(timeIntervalSince1970: 500)), .changedOnDisk)
    }

    func testStalenessBlocksFileAppearingAfterScan() {
        XCTAssertEqual(LibraryBackup.staleness(loaded: nil, current: Date()), .appearedOnDisk)
    }

    func testStalenessAllowsFirstEverWrite() {
        // No file at scan time, still none now — creating it is the point
        XCTAssertNil(LibraryBackup.staleness(loaded: nil, current: nil))
    }

    func testStalenessAllowsUnreadableCurrentDate() {
        // Can't read mtime: don't block the user's sync on a stat failure
        XCTAssertNil(LibraryBackup.staleness(loaded: Date(), current: nil))
    }

    func testModificationDateOfMissingFileIsNil() {
        XCTAssertNil(LibraryBackup.modificationDate(of: dir.appendingPathComponent("nope.xml").path))
    }
}
