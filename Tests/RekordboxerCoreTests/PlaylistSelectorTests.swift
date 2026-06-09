import XCTest
@testable import RekordboxerCore

final class PlaylistSelectorTests: XCTestCase {

    // MARK: - Helpers

    private func playlist(_ name: String, keys: [Int] = []) -> PlaylistNode {
        PlaylistNode(type: .playlist, name: name, children: [], trackKeys: keys)
    }

    private func folder(_ name: String, _ children: [PlaylistNode]) -> PlaylistNode {
        PlaylistNode(type: .folder, name: name, children: children, trackKeys: [])
    }

    // MARK: - path(for:prefix:)

    func testPathEmptyPrefix() {
        XCTAssertEqual(PlaylistSelector.path(for: "House", prefix: ""), "House")
    }

    func testPathNonEmptyPrefix() {
        XCTAssertEqual(PlaylistSelector.path(for: "Deep", prefix: "House"), "House/Deep")
    }

    func testPathNestedPrefix() {
        XCTAssertEqual(PlaylistSelector.path(for: "Minimal", prefix: "House/Techno"), "House/Techno/Minimal")
    }

    // MARK: - allPaths(node:prefix:)

    func testAllPathsFlatPlaylist() {
        let node = playlist("Summer Set")
        XCTAssertEqual(PlaylistSelector.allPaths(node: node, prefix: ""), ["Summer Set"])
    }

    func testAllPathsPlaylistWithPrefix() {
        let node = playlist("Summer Set")
        XCTAssertEqual(PlaylistSelector.allPaths(node: node, prefix: "House"), ["House/Summer Set"])
    }

    func testAllPathsFolderWithChildren() {
        let node = folder("House", [playlist("Deep House"), playlist("Techno")])
        XCTAssertEqual(PlaylistSelector.allPaths(node: node, prefix: ""), ["House/Deep House", "House/Techno"])
    }

    func testAllPathsEmptyFolderIsEmpty() {
        XCTAssertEqual(PlaylistSelector.allPaths(node: folder("Empty", []), prefix: ""), [])
    }

    func testAllPathsNestedFolders() {
        let tree = folder("Root", [
            playlist("Direct"),
            folder("Sub", [playlist("Minimal")]),
        ])
        XCTAssertEqual(
            PlaylistSelector.allPaths(node: tree, prefix: ""),
            ["Root/Direct", "Root/Sub/Minimal"]
        )
    }

    func testAllPathsFolderWithPrefix() {
        let node = folder("Sets", [playlist("House"), playlist("Techno")])
        XCTAssertEqual(
            PlaylistSelector.allPaths(node: node, prefix: "DJ"),
            ["DJ/Sets/House", "DJ/Sets/Techno"]
        )
    }

    // MARK: - checkState(for:prefix:selected:)

    func testCheckStatePlaylistSelected() {
        let node = playlist("Deep House")
        XCTAssertEqual(
            PlaylistSelector.checkState(for: node, prefix: "", selected: ["Deep House"]),
            .checked
        )
    }

    func testCheckStatePlaylistNotSelected() {
        let node = playlist("Deep House")
        XCTAssertEqual(
            PlaylistSelector.checkState(for: node, prefix: "", selected: []),
            .unchecked
        )
    }

    func testCheckStatePlaylistWrongPath() {
        let node = playlist("Deep House")
        // Must match full path including prefix
        XCTAssertEqual(
            PlaylistSelector.checkState(for: node, prefix: "House", selected: ["Deep House"]),
            .unchecked
        )
        XCTAssertEqual(
            PlaylistSelector.checkState(for: node, prefix: "House", selected: ["House/Deep House"]),
            .checked
        )
    }

    func testCheckStateFolderAllSelected() {
        let node = folder("House", [playlist("Deep"), playlist("Techno")])
        let selected: Set<String> = ["House/Deep", "House/Techno"]
        XCTAssertEqual(PlaylistSelector.checkState(for: node, prefix: "", selected: selected), .checked)
    }

    func testCheckStateFolderNoneSelected() {
        let node = folder("House", [playlist("Deep"), playlist("Techno")])
        XCTAssertEqual(PlaylistSelector.checkState(for: node, prefix: "", selected: []), .unchecked)
    }

    func testCheckStateFolderPartialSelection() {
        let node = folder("House", [playlist("Deep"), playlist("Techno")])
        XCTAssertEqual(
            PlaylistSelector.checkState(for: node, prefix: "", selected: ["House/Deep"]),
            .mixed
        )
    }

    func testCheckStateEmptyFolderIsUnchecked() {
        XCTAssertEqual(
            PlaylistSelector.checkState(for: folder("Empty", []), prefix: "", selected: ["Empty"]),
            .unchecked
        )
    }

    func testCheckStateNestedFolderMixed() {
        let tree = folder("Root", [
            playlist("A"),
            folder("Sub", [playlist("B"), playlist("C")]),
        ])
        // A and B selected, C not — mixed overall
        let selected: Set<String> = ["Root/A", "Root/Sub/B"]
        XCTAssertEqual(PlaylistSelector.checkState(for: tree, prefix: "", selected: selected), .mixed)
    }

    func testCheckStateNestedFolderAllSelected() {
        let tree = folder("Root", [
            playlist("A"),
            folder("Sub", [playlist("B")]),
        ])
        let selected: Set<String> = ["Root/A", "Root/Sub/B"]
        XCTAssertEqual(PlaylistSelector.checkState(for: tree, prefix: "", selected: selected), .checked)
    }

    // MARK: - collectTrackKeys(from:prefix:selected:into:)

    func testCollectFromSelectedPlaylist() {
        var keys: [Int] = []
        PlaylistSelector.collectTrackKeys(from: playlist("House", keys: [1, 2, 3]), prefix: "", selected: ["House"], into: &keys)
        XCTAssertEqual(keys, [1, 2, 3])
    }

    func testCollectSkipsUnselectedPlaylist() {
        var keys: [Int] = []
        PlaylistSelector.collectTrackKeys(from: playlist("Techno", keys: [4, 5]), prefix: "", selected: ["House"], into: &keys)
        XCTAssertTrue(keys.isEmpty)
    }

    func testCollectFromFolderSelectsMatchingChildren() {
        let node = folder("DJ Sets", [
            playlist("House Set", keys: [1, 2]),
            playlist("Techno Set", keys: [3, 4]),
        ])
        var keys: [Int] = []
        PlaylistSelector.collectTrackKeys(from: node, prefix: "", selected: ["DJ Sets/House Set"], into: &keys)
        XCTAssertEqual(keys, [1, 2])
    }

    func testCollectFromFolderAllChildren() {
        let node = folder("All", [
            playlist("A", keys: [1]),
            playlist("B", keys: [2]),
        ])
        var keys: [Int] = []
        PlaylistSelector.collectTrackKeys(from: node, prefix: "", selected: ["All/A", "All/B"], into: &keys)
        XCTAssertEqual(Set(keys), [1, 2])
    }

    func testCollectFromNestedFolders() {
        let tree = folder("Root", [
            playlist("Direct", keys: [1, 2]),
            folder("Sub", [playlist("Minimal", keys: [10, 11])]),
        ])
        var keys: [Int] = []
        PlaylistSelector.collectTrackKeys(from: tree, prefix: "", selected: ["Root/Direct", "Root/Sub/Minimal"], into: &keys)
        XCTAssertEqual(Set(keys), [1, 2, 10, 11])
    }

    func testCollectWithPrefix() {
        let node = playlist("Techno", keys: [7, 8])
        var keys: [Int] = []
        PlaylistSelector.collectTrackKeys(from: node, prefix: "DJ", selected: ["DJ/Techno"], into: &keys)
        XCTAssertEqual(keys, [7, 8])
    }

    func testCollectPreservesOrderWithinPlaylist() {
        let node = playlist("Ordered", keys: [3, 1, 2])
        var keys: [Int] = []
        PlaylistSelector.collectTrackKeys(from: node, prefix: "", selected: ["Ordered"], into: &keys)
        XCTAssertEqual(keys, [3, 1, 2])
    }

    func testCollectAppendsToExistingKeys() {
        let node = playlist("More", keys: [5, 6])
        var keys: [Int] = [1, 2]
        PlaylistSelector.collectTrackKeys(from: node, prefix: "", selected: ["More"], into: &keys)
        XCTAssertEqual(keys, [1, 2, 5, 6])
    }
}
