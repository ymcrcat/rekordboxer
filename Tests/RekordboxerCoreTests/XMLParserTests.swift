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
