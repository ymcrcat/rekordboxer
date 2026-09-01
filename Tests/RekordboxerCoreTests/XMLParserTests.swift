import XCTest
@testable import RekordboxerCore

final class XMLParserTests: XCTestCase {
    var library: RekordboxLibrary!

    override func setUp() {
        let fixturePath = Bundle.module.path(forResource: "test_library", ofType: "xml", inDirectory: "Fixtures")!
        let data = try! Data(contentsOf: URL(fileURLWithPath: fixturePath))
        library = try! RekordboxXMLParser.parse(data: data)
    }

    func testProductInfo() {
        XCTAssertEqual(library.productName, "rekordbox")
        XCTAssertEqual(library.productVersion, "6.7.4")
        XCTAssertEqual(library.productCompany, "AlphaTheta")
    }

    func testTrackCount() {
        XCTAssertEqual(library.tracks.count, 2)
    }

    func testTrackMetadata() {
        let track = library.tracks[1]!
        XCTAssertEqual(track.name, "Summer Vibes")
        XCTAssertEqual(track.artist, "DJ Example")
        XCTAssertEqual(track.genre, "House")
        XCTAssertEqual(track.averageBpm, 126.0)
        XCTAssertEqual(track.tonality, "Am")
        XCTAssertEqual(track.rating, 255)
        XCTAssertEqual(track.totalTime, 238)
        XCTAssertEqual(track.location, "file://localhost/Users/dj/Music/Summer%20Vibes.mp3")
    }

    func testTempos() {
        let track = library.tracks[1]!
        XCTAssertEqual(track.tempos.count, 1)
        XCTAssertEqual(track.tempos[0].bpm, 126.0)
        XCTAssertEqual(track.tempos[0].inizio, 0.520)
        XCTAssertEqual(track.tempos[0].metro, "4/4")
        XCTAssertEqual(track.tempos[0].battito, 1)
    }

    func testPositionMarks() {
        let track = library.tracks[1]!
        XCTAssertEqual(track.positionMarks.count, 3)

        let memoryCue = track.positionMarks[0]
        XCTAssertTrue(memoryCue.isMemoryCue)
        XCTAssertEqual(memoryCue.type, .cue)

        let hotCue = track.positionMarks[1]
        XCTAssertTrue(hotCue.isHotCue)
        XCTAssertEqual(hotCue.num, 0)
        XCTAssertEqual(hotCue.name, "Drop")
        XCTAssertEqual(hotCue.red, 40)

        let loop = track.positionMarks[2]
        XCTAssertTrue(loop.isLoop)
        XCTAssertEqual(loop.start, 112.520)
        XCTAssertEqual(loop.end, 116.520)
    }

    func testExternalEntitiesAreNotResolved() throws {
        // XXE hardening: an external entity must never leak file contents
        let secretFile = FileManager.default.temporaryDirectory.appendingPathComponent("xxe-\(UUID().uuidString).txt")
        try Data("SECRET-CONTENT".utf8).write(to: secretFile)
        defer { try? FileManager.default.removeItem(at: secretFile) }

        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE DJ_PLAYLISTS [<!ENTITY xxe SYSTEM "file://\(secretFile.path)">]>
        <DJ_PLAYLISTS Version="1.0.0">
          <COLLECTION Entries="1">
            <TRACK TrackID="1" Name="&xxe;"/>
          </COLLECTION>
        </DJ_PLAYLISTS>
        """
        // Either the parse fails outright or the entity stays unresolved —
        // the secret must never appear in parsed data
        if let library = try? RekordboxXMLParser.parse(data: Data(xml.utf8)) {
            let name = library.tracks[1]?.name ?? ""
            XCTAssertFalse(name.contains("SECRET-CONTENT"))
        }
    }

    func testLocationKeyedPlaylistResolvesToTrackIDs() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <DJ_PLAYLISTS Version="1.0.0">
          <COLLECTION Entries="1">
            <TRACK TrackID="42" Name="T" Location="file://localhost/Users/dj/t.mp3"/>
          </COLLECTION>
          <PLAYLISTS>
            <NODE Type="0" Name="ROOT" Count="1">
              <NODE Type="1" Name="ByLocation" KeyType="1" Entries="1">
                <TRACK Key="file://localhost/Users/dj/t.mp3"/>
              </NODE>
            </NODE>
          </PLAYLISTS>
        </DJ_PLAYLISTS>
        """
        let lib = try RekordboxXMLParser.parse(data: Data(xml.utf8))
        XCTAssertEqual(lib.rootNode.children[0].trackKeys, [42])
    }

    func testPlaylistStructure() {
        let root = library.rootNode
        XCTAssertTrue(root.isFolder)
        XCTAssertEqual(root.name, "ROOT")
        XCTAssertEqual(root.children.count, 1)

        let folder = root.children[0]
        XCTAssertTrue(folder.isFolder)
        XCTAssertEqual(folder.name, "Club Sets")

        let playlist = folder.children[0]
        XCTAssertTrue(playlist.isPlaylist)
        XCTAssertEqual(playlist.name, "Friday Night")
        XCTAssertEqual(playlist.trackKeys, [1, 2])
    }
}
