import XCTest
@testable import RekordboxerCore

final class SyncEngineTests: XCTestCase {
    func testDiffDetectsNewTracks() {
        let library = RekordboxLibrary()
        let folders = [
            ScannedFolder(folderName: "House", folderURL: URL(fileURLWithPath: "/music/House"), files: [
                ScannedFile(url: URL(fileURLWithPath: "/music/House/track1.mp3"), size: 1000, modificationDate: Date()),
            ])
        ]

        let diff = SyncEngine.diff(library: library, scannedFolders: folders)
        XCTAssertEqual(diff.newTracks.count, 1)
        XCTAssertEqual(diff.removedTracks.count, 0)
        XCTAssertEqual(diff.newTracks[0].url.lastPathComponent, "track1.mp3")
    }

    func testDiffDetectsRemovedTracks() {
        var library = RekordboxLibrary()
        var track = Track(trackID: 1)
        track.location = Track.encodeLocation("/music/House/deleted.mp3")
        library.tracks[1] = track
        library.rootNode = PlaylistNode(type: .folder, name: "ROOT", children: [
            PlaylistNode(type: .playlist, name: "House", children: [], trackKeys: [1])
        ], trackKeys: [])

        let folders: [ScannedFolder] = [
            ScannedFolder(folderName: "House", folderURL: URL(fileURLWithPath: "/music/House"), files: [])
        ]

        let diff = SyncEngine.diff(library: library, scannedFolders: folders)
        XCTAssertEqual(diff.removedTracks.count, 1)
        XCTAssertEqual(diff.removedTracks[0].trackID, 1)
    }

    func testDiffDetectsExistingTracks() {
        var library = RekordboxLibrary()
        var track = Track(trackID: 1)
        track.location = Track.encodeLocation("/music/House/existing.mp3")
        library.tracks[1] = track

        let folders = [
            ScannedFolder(folderName: "House", folderURL: URL(fileURLWithPath: "/music/House"), files: [
                ScannedFile(url: URL(fileURLWithPath: "/music/House/existing.mp3"), size: 1000, modificationDate: Date()),
            ])
        ]

        let diff = SyncEngine.diff(library: library, scannedFolders: folders)
        XCTAssertEqual(diff.newTracks.count, 0)
        XCTAssertEqual(diff.removedTracks.count, 0)
        XCTAssertEqual(diff.unchangedCount, 1)
    }

    func testApplyAddsNewTracks() {
        var library = RekordboxLibrary()
        var idMap = TrackIDMap()

        let newFiles = [
            ScannedFile(url: URL(fileURLWithPath: "/music/House/new.mp3"), size: 5000, modificationDate: Date()),
        ]
        let diff = SyncDiff(
            newTracks: newFiles,
            removedTracks: [],
            unchangedCount: 0,
            playlistMapping: [("House", newFiles.map { $0.url })]
        )

        SyncEngine.apply(diff: diff, to: &library, idMap: &idMap, removals: [])

        XCTAssertEqual(library.tracks.count, 1)
        let track = library.tracks.values.first!
        XCTAssertEqual(track.name, "new")
        XCTAssertEqual(track.filePath, "/music/House/new.mp3")

        XCTAssertEqual(library.rootNode.children.count, 1)
        XCTAssertEqual(library.rootNode.children[0].name, "House")
        XCTAssertEqual(library.rootNode.children[0].trackKeys.count, 1)
    }

    func testApplyRemovesOnlyApprovedTracks() {
        var library = RekordboxLibrary()
        var idMap = TrackIDMap()

        var track1 = Track(trackID: 1)
        track1.location = Track.encodeLocation("/music/House/keep.mp3")
        var track2 = Track(trackID: 2)
        track2.location = Track.encodeLocation("/music/House/remove.mp3")
        library.tracks[1] = track1
        library.tracks[2] = track2
        idMap.assign(path: "/music/House/keep.mp3", trackID: 1)
        idMap.assign(path: "/music/House/remove.mp3", trackID: 2)

        let diff = SyncDiff(
            newTracks: [],
            removedTracks: [track2],
            unchangedCount: 1,
            playlistMapping: [("House", [URL(fileURLWithPath: "/music/House/keep.mp3")])]
        )

        SyncEngine.apply(diff: diff, to: &library, idMap: &idMap, removals: [2])

        XCTAssertEqual(library.tracks.count, 1)
        XCTAssertNotNil(library.tracks[1])
        XCTAssertNil(library.tracks[2])
    }

    func testTrackIDMapStability() {
        var idMap = TrackIDMap()
        let id1 = idMap.getOrAssign(path: "/music/track1.mp3")
        let id2 = idMap.getOrAssign(path: "/music/track2.mp3")
        let id1Again = idMap.getOrAssign(path: "/music/track1.mp3")

        XCTAssertEqual(id1, id1Again)
        XCTAssertNotEqual(id1, id2)
    }
}
