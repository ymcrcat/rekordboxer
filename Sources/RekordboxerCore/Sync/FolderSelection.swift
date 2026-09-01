import Foundation

/// Folder-tree selection logic for the sync UI: which folders are checked,
/// which are pre-selected on a rescan, and how the tree is pruned before
/// being handed to `SyncEngine`.
///
/// Lives in the core (not the view model) so it is reachable from tests.
public enum FolderSelection {
    /// Every folder path in the tree, including nested children.
    public static func allPaths(in folders: [ScannedFolder]) -> Set<String> {
        var result = Set<String>()
        for folder in folders {
            result.insert(folder.folderURL.path)
            result.formUnion(allPaths(in: folder.children))
        }
        return result
    }

    /// Tri-state check mark for one folder, derived from its whole subtree.
    public static func checkState(for folder: ScannedFolder, selected: Set<String>) -> CheckState {
        let paths = allPaths(in: [folder])
        let selectedCount = paths.filter { selected.contains($0) }.count
        if selectedCount == 0 { return .unchecked }
        if selectedCount == paths.count { return .checked }
        return .mixed
    }

    /// Pre-select only folders that have at least one file already in the library.
    /// Pure container folders (no direct files) are selected if all their
    /// children are selected, so an untouched subtree stays fully checked.
    public static func preselect(in folders: [ScannedFolder], existingPaths: Set<String>) -> Set<String> {
        var result = Set<String>()
        for folder in folders {
            let childResults = preselect(in: folder.children, existingPaths: existingPaths)
            result.formUnion(childResults)

            if !folder.files.isEmpty {
                if folder.files.contains(where: { existingPaths.contains($0.path) }) {
                    result.insert(folder.folderURL.path)
                }
            } else if !folder.children.isEmpty {
                if folder.children.allSatisfy({ childResults.contains($0.folderURL.path) }) {
                    result.insert(folder.folderURL.path)
                }
            }
        }
        return result
    }

    /// Prune the tree to selected folders. An unselected folder with selected
    /// descendants survives as a container with no direct files, so the
    /// playlist hierarchy keeps its shape.
    public static func filter(_ folders: [ScannedFolder], selectedPaths: Set<String>) -> [ScannedFolder] {
        folders.compactMap { folder -> ScannedFolder? in
            let isSelected = selectedPaths.contains(folder.folderURL.path)
            let filteredChildren = filter(folder.children, selectedPaths: selectedPaths)

            if isSelected {
                return ScannedFolder(
                    folderName: folder.folderName,
                    folderURL: folder.folderURL,
                    files: folder.files,
                    children: filteredChildren
                )
            } else if !filteredChildren.isEmpty {
                return ScannedFolder(
                    folderName: folder.folderName,
                    folderURL: folder.folderURL,
                    files: [],
                    children: filteredChildren
                )
            }
            return nil
        }
    }

    /// Track IDs to remove: the user's explicit removal checkmarks, plus every
    /// library track whose file was scanned but sits in an unselected folder.
    public static func removals(
        userSelected: Set<Int>,
        library: RekordboxLibrary,
        allScannedPaths: Set<String>,
        selectedPaths: Set<String>
    ) -> Set<Int> {
        let excluded = allScannedPaths.subtracting(selectedPaths)
        var removals = userSelected
        for (trackID, track) in library.tracks where excluded.contains(track.filePath) {
            removals.insert(trackID)
        }
        return removals
    }
}
