import XCTest
@testable import RekordboxerCore

final class ModelTests: XCTestCase {
    func testTrackRatingConversion() {
        XCTAssertEqual(Track.ratingToStars(0), 0)
        XCTAssertEqual(Track.ratingToStars(51), 1)
        XCTAssertEqual(Track.ratingToStars(102), 2)
        XCTAssertEqual(Track.ratingToStars(153), 3)
        XCTAssertEqual(Track.ratingToStars(204), 4)
        XCTAssertEqual(Track.ratingToStars(255), 5)

        XCTAssertEqual(Track.starsToRating(0), 0)
        XCTAssertEqual(Track.starsToRating(3), 153)
        XCTAssertEqual(Track.starsToRating(5), 255)
    }

    func testPositionMarkIsHotCue() {
        let hotCue = PositionMark(name: "Drop", type: .cue, start: 32.5, end: nil, num: 0, red: 40, green: 226, blue: 20)
        XCTAssertTrue(hotCue.isHotCue)
        XCTAssertFalse(hotCue.isMemoryCue)

        let memoryCue = PositionMark(name: "", type: .cue, start: 0.5, end: nil, num: -1, red: nil, green: nil, blue: nil)
        XCTAssertFalse(memoryCue.isHotCue)
        XCTAssertTrue(memoryCue.isMemoryCue)
    }

    func testPositionMarkIsLoop() {
        let hotLoop = PositionMark(name: "Build", type: .loop, start: 128.0, end: 132.0, num: 2, red: 255, green: 150, blue: 0)
        XCTAssertTrue(hotLoop.isLoop)
        XCTAssertTrue(hotLoop.isHotCue)

        let memoryLoop = PositionMark(name: "", type: .loop, start: 96.0, end: 128.0, num: -1, red: nil, green: nil, blue: nil)
        XCTAssertTrue(memoryLoop.isLoop)
        XCTAssertTrue(memoryLoop.isMemoryCue)
    }

    func testTrackLocationEncoding() {
        let path = "/Users/dj/Music/Summer Vibes.mp3"
        let encoded = Track.encodeLocation(path)
        XCTAssertEqual(encoded, "file://localhost/Users/dj/Music/Summer%20Vibes.mp3")

        let decoded = Track.decodeLocation(encoded)
        XCTAssertEqual(decoded, path)
    }

    func testDecodeLocationVariants() {
        // Some tools write file:/// (no localhost)
        XCTAssertEqual(Track.decodeLocation("file:///Users/dj/Music/track.mp3"), "/Users/dj/Music/track.mp3")
        // Prefix is only stripped at the start of the string
        XCTAssertEqual(Track.decodeLocation("/weird/file://localhost/x.mp3"), "/weird/file://localhost/x.mp3")
    }

    func testDecodeLocationNormalizesUnicode() {
        // Decomposed "é" (e + combining accent) must decode to precomposed form
        let decomposed = "/Users/dj/Music/Caf\u{0065}\u{0301}.mp3"
        let precomposed = "/Users/dj/Music/Caf\u{00E9}.mp3"
        XCTAssertEqual(Track.decodeLocation(Track.encodeLocation(decomposed)), precomposed)
    }

    func testPlaylistNodeTypes() {
        let folder = PlaylistNode(type: .folder, name: "House", children: [], trackKeys: [])
        XCTAssertTrue(folder.isFolder)
        XCTAssertFalse(folder.isPlaylist)

        let playlist = PlaylistNode(type: .playlist, name: "Summer Set", children: [], trackKeys: [1, 2, 3])
        XCTAssertFalse(playlist.isFolder)
        XCTAssertTrue(playlist.isPlaylist)
    }
}
