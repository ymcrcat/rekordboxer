import XCTest
@testable import RekordboxerCore

final class XMLWriterTests: XCTestCase {
    func testRoundTrip() throws {
        let fixturePath = Bundle.module.path(forResource: "test_library", ofType: "xml", inDirectory: "Fixtures")!
        let originalData = try Data(contentsOf: URL(fileURLWithPath: fixturePath))
        let library = try RekordboxXMLParser.parse(data: originalData)

        let writtenData = try RekordboxXMLWriter.write(library: library)
        let reparsed = try RekordboxXMLParser.parse(data: writtenData)

        XCTAssertEqual(reparsed.tracks.count, library.tracks.count)
        for (id, original) in library.tracks {
            let rt = reparsed.tracks[id]!
            XCTAssertEqual(rt.name, original.name)
            XCTAssertEqual(rt.artist, original.artist)
            XCTAssertEqual(rt.location, original.location)
            XCTAssertEqual(rt.averageBpm, original.averageBpm)
            XCTAssertEqual(rt.rating, original.rating)
            XCTAssertEqual(rt.tempos.count, original.tempos.count)
            XCTAssertEqual(rt.positionMarks.count, original.positionMarks.count)
        }

        XCTAssertEqual(reparsed.rootNode.children.count, library.rootNode.children.count)
        let playlist = reparsed.rootNode.children[0].children[0]
        XCTAssertEqual(playlist.name, "Friday Night")
        XCTAssertEqual(playlist.trackKeys, [1, 2])
    }

    func testWriteNewTrack() throws {
        var library = RekordboxLibrary()
        var track = Track(trackID: 1)
        track.name = "Test Track"
        track.artist = "Test Artist"
        track.location = Track.encodeLocation("/Users/dj/Music/test.mp3")
        track.averageBpm = 128.0
        library.tracks[1] = track

        let playlist = PlaylistNode(type: .playlist, name: "Test Playlist", children: [], trackKeys: [1])
        library.rootNode = PlaylistNode(type: .folder, name: "ROOT", children: [playlist], trackKeys: [])

        let data = try RekordboxXMLWriter.write(library: library)
        let reparsed = try RekordboxXMLParser.parse(data: data)

        XCTAssertEqual(reparsed.tracks.count, 1)
        XCTAssertEqual(reparsed.tracks[1]!.name, "Test Track")
        XCTAssertEqual(reparsed.rootNode.children[0].trackKeys, [1])
    }

    func testParsedTracksRoundTripVerbatim() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <DJ_PLAYLISTS Version="1.0.0">
          <COLLECTION Entries="1">
            <TRACK TrackID="7" Name="Verbatim" AverageBpm="128.000" Location="file://localhost/Users/dj/v.mp3">
              <TEMPO Inizio="0.5250" Bpm="128.000" Metro="4/4" Battito="1"/>
              <CUSTOM_TAG Foo="bar"/>
            </TRACK>
          </COLLECTION>
          <PLAYLISTS><NODE Type="0" Name="ROOT" Count="0"/></PLAYLISTS>
        </DJ_PLAYLISTS>
        """
        let library = try RekordboxXMLParser.parse(data: Data(xml.utf8))
        let written = String(data: try RekordboxXMLWriter.write(library: library), encoding: .utf8)!

        // Original attribute formatting survives (no %.2f canonicalization)
        XCTAssertTrue(written.contains("AverageBpm=\"128.000\""))
        XCTAssertTrue(written.contains("Inizio=\"0.5250\""))
        // Child elements the app doesn't model are preserved
        XCTAssertTrue(written.contains("CUSTOM_TAG"))
        // Attributes absent in the original stay absent
        XCTAssertFalse(written.contains("Composer="))
    }

    func testUnparseableRawChildFailsLoudly() throws {
        var library = RekordboxLibrary()
        var track = Track(trackID: 1)
        track.rawAttributes = ["TrackID": "1"]
        track.rawChildrenXML = ["<not-valid-xml"]
        library.tracks[1] = track

        // Losslessness path must fail loudly, never silently drop a child
        XCTAssertThrowsError(try RekordboxXMLWriter.write(library: library))
    }

    func testXMLContainsDeclaration() throws {
        let library = RekordboxLibrary()
        let data = try RekordboxXMLWriter.write(library: library)
        let xmlString = String(data: data, encoding: .utf8)!
        XCTAssertTrue(xmlString.hasPrefix("<?xml"))
        XCTAssertTrue(xmlString.contains("DJ_PLAYLISTS"))
        XCTAssertTrue(xmlString.contains("Version=\"1.0.0\""))
    }
}
