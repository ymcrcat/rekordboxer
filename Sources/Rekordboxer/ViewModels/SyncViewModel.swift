import Foundation
import RekordboxerCore

enum CheckState {
    case checked, unchecked, mixed
}

@MainActor
final class SyncViewModel: ObservableObject {
    @Published var library = RekordboxLibrary()
    @Published var diff: SyncDiff?
    @Published var removalSelections: Set<Int> = []
    @Published var statusMessage: String = ""
    @Published var errorMessage: String?
    @Published var isScanning: Bool = false
    @Published var selectedFolders: Set<String> = []
    @Published var scannedFolders: [ScannedFolder] = []
    @Published var syncSuccess: Bool = false

    private var settings = AppSettings()
    private var idMap = TrackIDMap()

    func loadOnAppear() {
        do {
            settings = try AppSettings.load(from: AppSettings.defaultURL)
        } catch {
            settings = AppSettings()
        }

        do {
            idMap = try TrackIDMap.load(from: AppSettings.trackIDMapURL)
        } catch {
            idMap = TrackIDMap()
        }

        loadLibrary()

        if !settings.sourceFolderPath.isEmpty {
            scan()
        }
    }

    private func loadLibrary() {
        let xmlPath = settings.xmlFilePath
        guard !xmlPath.isEmpty else {
            statusMessage = "No XML file configured. Go to Settings to set the path."
            return
        }

        let url = URL(fileURLWithPath: xmlPath)
        guard FileManager.default.fileExists(atPath: xmlPath) else {
            statusMessage = "XML file not found. Scan to create it."
            library = RekordboxLibrary()
            return
        }

        do {
            let data = try Data(contentsOf: url)
            library = try RekordboxXMLParser.parse(data: data)
            statusMessage = "Library loaded: \(library.tracks.count) tracks"
        } catch {
            errorMessage = "Failed to load XML: \(error.localizedDescription)"
            library = RekordboxLibrary()
        }
    }

    func scan() {
        errorMessage = nil
        diff = nil
        removalSelections = []
        scannedFolders = []
        selectedFolders = []
        syncSuccess = false

        // Reload settings and XML in case the user changed paths
        do {
            settings = try AppSettings.load(from: AppSettings.defaultURL)
        } catch {
            settings = AppSettings()
        }
        do {
            idMap = try TrackIDMap.load(from: AppSettings.trackIDMapURL)
        } catch {
            idMap = TrackIDMap()
        }
        loadLibrary()

        let sourcePath = settings.sourceFolderPath
        guard !sourcePath.isEmpty else {
            errorMessage = "No source folder configured. Go to Settings to set the path."
            return
        }

        isScanning = true
        statusMessage = "Scanning..."

        let sourceURL = URL(fileURLWithPath: sourcePath)

        Task {
            do {
                let folders = try FolderScanner.scan(root: sourceURL)
                let result = SyncEngine.diff(library: library, scannedFolders: folders)
                self.diff = result
                self.scannedFolders = folders
                if self.library.tracks.isEmpty {
                    self.selectedFolders = Self.allFolderPaths(in: folders)
                } else {
                    let existingPaths = Set(self.library.tracks.values.map { $0.filePath })
                    self.selectedFolders = Self.preselectFolders(in: folders, existingPaths: existingPaths)
                }
                self.removalSelections = Set(result.removedTracks.map { $0.trackID })
                self.statusMessage = "\(result.newTracks.count) new, \(result.removedTracks.count) removed, \(result.unchangedCount) unchanged"
            } catch {
                self.errorMessage = "Scan failed: \(error.localizedDescription)"
            }
            self.isScanning = false
        }
    }

    // MARK: - Folder Selection

    func toggleFolder(_ folder: ScannedFolder) {
        let paths = Self.allFolderPaths(in: [folder])
        if folderCheckState(folder) == .checked {
            selectedFolders.subtract(paths)
        } else {
            selectedFolders.formUnion(paths)
        }
    }

    func isFolderSelected(_ folder: ScannedFolder) -> Bool {
        selectedFolders.contains(folder.folderURL.path)
    }

    func folderCheckState(_ folder: ScannedFolder) -> CheckState {
        let allPaths = Self.allFolderPaths(in: [folder])
        let selectedCount = allPaths.filter { selectedFolders.contains($0) }.count
        if selectedCount == 0 {
            return .unchecked
        } else if selectedCount == allPaths.count {
            return .checked
        } else {
            return .mixed
        }
    }

    static func allFolderPaths(in folders: [ScannedFolder]) -> Set<String> {
        var result = Set<String>()
        for folder in folders {
            result.insert(folder.folderURL.path)
            result.formUnion(allFolderPaths(in: folder.children))
        }
        return result
    }

    /// Pre-select only folders that have at least one file already in the library.
    /// Pure container folders (no direct files) are selected if all their children are selected.
    static func preselectFolders(in folders: [ScannedFolder], existingPaths: Set<String>) -> Set<String> {
        var result = Set<String>()
        for folder in folders {
            let childResults = preselectFolders(in: folder.children, existingPaths: existingPaths)
            result.formUnion(childResults)

            if !folder.files.isEmpty {
                // Has direct files: select if any file is already in the library
                if folder.files.contains(where: { existingPaths.contains($0.url.path) }) {
                    result.insert(folder.folderURL.path)
                }
            } else if !folder.children.isEmpty {
                // Pure container: select if all children are selected
                if folder.children.allSatisfy({ childResults.contains($0.folderURL.path) }) {
                    result.insert(folder.folderURL.path)
                }
            }
        }
        return result
    }

    // MARK: - Filtered Sync

    func syncToXML() {
        guard let diff = diff else { return }
        errorMessage = nil

        do {
            let filteredFolders = Self.filterFolders(scannedFolders, selectedPaths: selectedFolders)
            let filteredFiles = filteredFolders.flatMap { $0.allFiles }
            let filteredFilePaths = Set(filteredFiles.map { $0.url.path })
            let filteredNewTracks = diff.newTracks.filter { filteredFilePaths.contains($0.url.path) }

            // Remove existing tracks that belong to unselected folders
            let allScannedPaths = Set(scannedFolders.flatMap { $0.allFiles }.map { $0.url.path })
            let excludedPaths = allScannedPaths.subtracting(filteredFilePaths)
            var removals = removalSelections
            for (trackID, track) in library.tracks {
                if excludedPaths.contains(track.filePath) {
                    removals.insert(trackID)
                }
            }

            let filteredDiff = SyncDiff(
                newTracks: filteredNewTracks,
                removedTracks: diff.removedTracks,
                unchangedCount: diff.unchangedCount,
                scannedFolders: filteredFolders
            )

            SyncEngine.apply(diff: filteredDiff, to: &library, idMap: &idMap, removals: removals)

            let xmlPath = settings.xmlFilePath
            guard !xmlPath.isEmpty else {
                errorMessage = "No XML file path configured."
                return
            }

            let data = try RekordboxXMLWriter.write(library: library)
            try data.write(to: URL(fileURLWithPath: xmlPath))
            try idMap.save(to: AppSettings.trackIDMapURL)

            // Create an empty diff to keep showing folder structure
            self.diff = SyncDiff(
                newTracks: [],
                removedTracks: [],
                unchangedCount: library.tracks.count,
                scannedFolders: scannedFolders
            )
            self.removalSelections = []
            self.syncSuccess = true
            statusMessage = "Synced! Library now has \(library.tracks.count) tracks."
        } catch {
            errorMessage = "Sync failed: \(error.localizedDescription)"
        }
    }

    /// Recursively prune the folder tree to only include selected folders.
    static func filterFolders(_ folders: [ScannedFolder], selectedPaths: Set<String>) -> [ScannedFolder] {
        folders.compactMap { folder -> ScannedFolder? in
            let isSelected = selectedPaths.contains(folder.folderURL.path)
            let filteredChildren = filterFolders(folder.children, selectedPaths: selectedPaths)

            if isSelected {
                return ScannedFolder(
                    folderName: folder.folderName,
                    folderURL: folder.folderURL,
                    files: folder.files,
                    children: filteredChildren
                )
            } else if !filteredChildren.isEmpty {
                // Parent not selected but some descendants are — keep as container with no direct files
                return ScannedFolder(
                    folderName: folder.folderName,
                    folderURL: folder.folderURL,
                    files: [],
                    children: filteredChildren
                )
            } else {
                return nil
            }
        }
    }

    var selectedNewTrackCount: Int {
        guard diff != nil else { return 0 }
        let filteredFolders = Self.filterFolders(scannedFolders, selectedPaths: selectedFolders)
        let filteredFilePaths = Set(filteredFolders.flatMap { $0.allFiles }.map { $0.url.path })
        return diff!.newTracks.filter { filteredFilePaths.contains($0.url.path) }.count
    }

    var selectedFolderCount: Int {
        selectedFolders.count
    }
}
