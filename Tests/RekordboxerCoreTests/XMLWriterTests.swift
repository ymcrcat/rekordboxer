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

    func testXMLContainsDeclaration() throws {
        let library = RekordboxLibrary()
        let data = try RekordboxXMLWriter.write(library: library)
        let xmlString = String(data: data, encoding: .utf8)!
        XCTAssertTrue(xmlString.hasPrefix("<?xml"))
        XCTAssertTrue(xmlString.contains("DJ_PLAYLISTS"))
        XCTAssertTrue(xmlString.contains("Version=\"1.0.0\""))
    }
}
