import XCTest
@testable import RekordboxerCore

final class FolderSelectionTests: XCTestCase {
    // /music/House/{intro.mp3, Deep/{smooth.mp3}}, /music/Techno/{dark.mp3}
    private func file(_ path: String) -> ScannedFile {
        ScannedFile(url: URL(fileURLWithPath: path), size: 100, modificationDate: Date())
    }

    private func tree() -> [ScannedFolder] {
        [
            ScannedFolder(
                folderName: "House",
                folderURL: URL(fileURLWithPath: "/music/House"),
                files: [file("/music/House/intro.mp3")],
                children: [
                    ScannedFolder(
                        folderName: "Deep",
                        folderURL: URL(fileURLWithPath: "/music/House/Deep"),
                        files: [file("/music/House/Deep/smooth.mp3")],
                        children: []
                    )
                ]
            ),
            ScannedFolder(
                folderName: "Techno",
                folderURL: URL(fileURLWithPath: "/music/Techno"),
                files: [file("/music/Techno/dark.mp3")],
                children: []
            ),
        ]
    }

    func testAllPathsIncludesNestedFolders() {
        XCTAssertEqual(
            FolderSelection.allPaths(in: tree()),
            ["/music/House", "/music/House/Deep", "/music/Techno"]
        )
    }

    func testCheckStateIsMixedWhenOnlyChildSelected() {
        let house = tree()[0]
        XCTAssertEqual(FolderSelection.checkState(for: house, selected: []), .unchecked)
        XCTAssertEqual(FolderSelection.checkState(for: house, selected: ["/music/House/Deep"]), .mixed)
        XCTAssertEqual(
            FolderSelection.checkState(for: house, selected: ["/music/House", "/music/House/Deep"]),
            .checked
        )
    }

    func testPreselectPicksFoldersAlreadyInLibrary() {
        // Only Techno's file is in the library — House stays unchecked
        let selected = FolderSelection.preselect(in: tree(), existingPaths: ["/music/Techno/dark.mp3"])
        XCTAssertEqual(selected, ["/music/Techno"])
    }

    func testPreselectChecksContainerWhenAllChildrenSelected() {
        // A container with no direct files rides on its children
        let container = [
            ScannedFolder(
                folderName: "Sets",
                folderURL: URL(fileURLWithPath: "/music/Sets"),
                files: [],
                children: [
                    ScannedFolder(folderName: "A", folderURL: URL(fileURLWithPath: "/music/Sets/A"),
                                  files: [file("/music/Sets/A/a.mp3")], children: []),
                    ScannedFolder(folderName: "B", folderURL: URL(fileURLWithPath: "/music/Sets/B"),
                                  files: [file("/music/Sets/B/b.mp3")], children: []),
                ]
            )
        ]
        let all = FolderSelection.preselect(
            in: container,
            existingPaths: ["/music/Sets/A/a.mp3", "/music/Sets/B/b.mp3"]
        )
        XCTAssertTrue(all.contains("/music/Sets"))

        // One child missing from the library -> container not auto-checked
        let partial = FolderSelection.preselect(in: container, existingPaths: ["/music/Sets/A/a.mp3"])
        XCTAssertFalse(partial.contains("/music/Sets"))
    }

    func testFilterKeepsUnselectedParentAsEmptyContainer() {
        // Selecting only the nested folder must preserve the hierarchy shape,
        // without dragging the parent's own files along
        let filtered = FolderSelection.filter(tree(), selectedPaths: ["/music/House/Deep"])
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].folderName, "House")
        XCTAssertEqual(filtered[0].files.count, 0, "parent's own files must be excluded")
        XCTAssertEqual(filtered[0].children.map(\.folderName), ["Deep"])
        XCTAssertEqual(filtered[0].allFiles.count, 1)
    }

    func testFilterDropsFullyUnselectedBranches() {
        XCTAssertEqual(FolderSelection.filter(tree(), selectedPaths: ["/music/Techno"]).map(\.folderName), ["Techno"])
        XCTAssertTrue(FolderSelection.filter(tree(), selectedPaths: []).isEmpty)
    }

    func testRemovalsCombineUserChecksAndDeselectedFolders() {
        var library = RekordboxLibrary()
        var keep = Track(trackID: 1)
        keep.location = Track.encodeLocation("/music/Techno/dark.mp3")
        var dropped = Track(trackID: 2)
        dropped.location = Track.encodeLocation("/music/House/intro.mp3")
        var userChecked = Track(trackID: 3)
        userChecked.location = Track.encodeLocation("/music/Techno/old.mp3")
        library.tracks = [1: keep, 2: dropped, 3: userChecked]

        let removals = FolderSelection.removals(
            userSelected: [3],
            library: library,
            allScannedPaths: ["/music/Techno/dark.mp3", "/music/House/intro.mp3"],
            selectedPaths: ["/music/Techno/dark.mp3"]
        )

        XCTAssertEqual(removals, [2, 3], "deselected folder's track plus the user's explicit check")
        XCTAssertFalse(removals.contains(1))
    }

    func testRemovalsSpareTracksOutsideTheScannedRoot() {
        // A track living outside the source folder was never scanned, so it
        // must not be swept up as "deselected"
        var library = RekordboxLibrary()
        var external = Track(trackID: 9)
        external.location = Track.encodeLocation("/elsewhere/guest-mix.mp3")
        library.tracks[9] = external

        let removals = FolderSelection.removals(
            userSelected: [],
            library: library,
            allScannedPaths: ["/music/Techno/dark.mp3"],
            selectedPaths: []
        )
        XCTAssertTrue(removals.isEmpty)
    }
}
