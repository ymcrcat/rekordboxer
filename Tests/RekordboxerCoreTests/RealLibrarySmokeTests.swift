import XCTest
@testable import RekordboxerCore

/// Read-only fidelity check against a real rekordbox export.
/// Skipped unless REKORDBOXER_REAL_XML is set. Never writes to that path.
final class RealLibrarySmokeTests: XCTestCase {
    func testRealLibraryRoundTripsWithoutLoss() throws {
        guard let path = ProcessInfo.processInfo.environment["REKORDBOXER_REAL_XML"] else {
            throw XCTSkip("REKORDBOXER_REAL_XML not set")
        }
        let original = try Data(contentsOf: URL(fileURLWithPath: path))

        let before = try RekordboxXMLParser.parse(data: original)
        let rewritten = try RekordboxXMLWriter.write(library: before)
        let after = try RekordboxXMLParser.parse(data: rewritten)

        // Nothing may vanish
        XCTAssertEqual(after.tracks.count, before.tracks.count, "track count changed")
        XCTAssertEqual(Set(after.tracks.keys), Set(before.tracks.keys), "TrackID set changed")

        var cuesBefore = 0, cuesAfter = 0, temposBefore = 0, temposAfter = 0
        for (id, b) in before.tracks {
            let a = after.tracks[id]!
            cuesBefore += b.positionMarks.count; cuesAfter += a.positionMarks.count
            temposBefore += b.tempos.count; temposAfter += a.tempos.count
            XCTAssertEqual(a.location, b.location, "location changed for \(id)")
            XCTAssertEqual(a.name, b.name, "name changed for \(id)")
            XCTAssertEqual(a.rating, b.rating, "rating changed for \(id)")
            XCTAssertEqual(a.averageBpm, b.averageBpm, "BPM changed for \(id)")
            // The whole point of the verbatim path: every original attribute survives
            XCTAssertEqual(a.rawAttributes, b.rawAttributes, "attributes changed for \(id)")
        }
        XCTAssertEqual(cuesAfter, cuesBefore, "cue points lost")
        XCTAssertEqual(temposAfter, temposBefore, "beatgrid markers lost")

        // Playlist tree survives
        func count(_ n: PlaylistNode) -> (Int, Int) {
            var nodes = 1, keys = n.trackKeys.count
            for c in n.children { let (dn, dk) = count(c); nodes += dn; keys += dk }
            return (nodes, keys)
        }
        XCTAssertEqual(count(after.rootNode).0, count(before.rootNode).0, "playlist nodes lost")
        XCTAssertEqual(count(after.rootNode).1, count(before.rootNode).1, "playlist entries lost")

        // Seeding an empty map against this library must not hand out a live ID
        var idMap = TrackIDMap()
        idMap.seed(from: before.tracks)
        let fresh = idMap.getOrAssign(path: "/tmp/brand-new-track-\(UUID().uuidString).mp3")
        XCTAssertNil(before.tracks[fresh], "new track would overwrite an existing one")

        try rewritten.write(to: URL(fileURLWithPath: "/tmp/rekordboxer-roundtrip.xml"))
        print("""
        REAL LIBRARY: \(before.tracks.count) tracks, \(cuesBefore) cues, \(temposBefore) tempos, \
        \(count(before.rootNode).0) playlist nodes | in \(original.count) B -> out \(rewritten.count) B \
        | next new ID \(fresh)
        """)
    }
}
