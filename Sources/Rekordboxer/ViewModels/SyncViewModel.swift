import Foundation
import RekordboxerCore

@MainActor
final class SyncViewModel: ObservableObject {
    @Published var library = RekordboxLibrary()
    @Published var diff: SyncDiff?
    @Published var removalSelections: Set<Int> = []
    @Published var statusMessage: String = ""
    @Published var errorMessage: String?
    @Published var isScanning: Bool = false
    @Published var isWritingXML: Bool = false
    @Published var selectedFolders: Set<String> = []
    @Published var scannedFolders: [ScannedFolder] = []
    @Published var syncSuccess: Bool = false

    private var settings = AppSettings()
    private var idMap = TrackIDMap()
    /// mtime of the XML when it was last loaded — used to detect edits made
    /// by rekordbox (or anything else) between scan and sync
    private var xmlLoadedModificationDate: Date?

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

        guard loadLibrary() else { return }
        idMap.seed(from: library.tracks)

        if !settings.sourceFolderPath.isEmpty {
            scan()
        }
    }

    /// Returns false when an existing XML file could not be read or parsed —
    /// proceeding would overwrite the user's library with an empty one.
    private func loadLibrary() -> Bool {
        let xmlPath = settings.xmlFilePath
        guard !xmlPath.isEmpty else {
            statusMessage = "No XML file configured. Go to Settings to set the path."
            return true
        }

        let url = URL(fileURLWithPath: xmlPath)
        guard FileManager.default.fileExists(atPath: xmlPath) else {
            statusMessage = "XML file not found. Scan to create it."
            library = RekordboxLibrary()
            xmlLoadedModificationDate = nil
            return true
        }

        do {
            let data = try Data(contentsOf: url)
            library = try RekordboxXMLParser.parse(data: data)
            xmlLoadedModificationDate = (try? FileManager.default.attributesOfItem(atPath: xmlPath))?[.modificationDate] as? Date
            statusMessage = "Library loaded: \(library.tracks.count) tracks"
            return true
        } catch {
            errorMessage = "Failed to load XML — fix or remove the file before syncing: \(error.localizedDescription)"
            library = RekordboxLibrary()
            return false
        }
    }

    func scan() {
        guard !isWritingXML else { return }
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
        guard loadLibrary() else { return }
        idMap.seed(from: library.tracks)

        let sourcePath = settings.sourceFolderPath
        guard !sourcePath.isEmpty else {
            errorMessage = "No source folder configured. Go to Settings to set the path."
            return
        }

        isScanning = true
        statusMessage = "Scanning..."

        let sourceURL = URL(fileURLWithPath: sourcePath)
        let librarySnapshot = library

        Task.detached(priority: .userInitiated) {
            do {
                let folders = try FolderScanner.scan(root: sourceURL)
                let result = SyncEngine.diff(library: librarySnapshot, scannedFolders: folders)
                await MainActor.run {
                    let existingPaths = Set(librarySnapshot.tracks.values.map { $0.filePath })
                    let newTrackPaths = Set(result.newTracks.map { $0.path })
                    let selected = librarySnapshot.tracks.isEmpty
                        ? SyncViewModel.allFolderPaths(in: folders)
                        : SyncViewModel.preselectFolders(in: folders, existingPaths: existingPaths.union(newTrackPaths))
                    self.diff = result
                    self.scannedFolders = folders
                    self.selectedFolders = selected
                    // Deletion requires an explicit check — never pre-checked
                    self.removalSelections = []
                    self.statusMessage = "\(result.newTracks.count) new, \(result.removedTracks.count) removed, \(result.unchangedCount) unchanged"
                    self.isScanning = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Scan failed: \(error.localizedDescription)"
                    self.isScanning = false
                }
            }
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
                if folder.files.contains(where: { existingPaths.contains($0.path) }) {
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
        guard !isWritingXML else { return }
        guard let diff = diff else {
            errorMessage = "No scan results. Run Scan first."
            return
        }
        errorMessage = nil
        syncSuccess = false

        let xmlPath = settings.xmlFilePath
        guard !xmlPath.isEmpty else {
            errorMessage = "No XML file path configured."
            return
        }

        // Refuse to overwrite edits made to the XML since the last scan.
        // Any mtime difference counts, and a file that appeared where none
        // existed at scan time counts too.
        let currentDate = (try? FileManager.default.attributesOfItem(atPath: xmlPath))?[.modificationDate] as? Date
        if let loadedDate = xmlLoadedModificationDate {
            if let currentDate, currentDate != loadedDate {
                errorMessage = "XML file changed on disk since the last scan. Refresh before syncing."
                return
            }
        } else if currentDate != nil {
            errorMessage = "An XML file appeared on disk since the last scan. Refresh before syncing."
            return
        }

        let filteredFolders = Self.filterFolders(scannedFolders, selectedPaths: selectedFolders)
        let filteredFiles = filteredFolders.flatMap { $0.allFiles }
        let filteredFilePaths = Set(filteredFiles.map { $0.path })
        let filteredNewTracks = diff.newTracks.filter { filteredFilePaths.contains($0.path) }

        // Remove existing tracks that belong to unselected folders
        let allScannedPaths = Set(scannedFolders.flatMap { $0.allFiles }.map { $0.path })
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

        // Serialization and disk writes happen off the main actor so a large
        // library can't freeze the UI
        let librarySnapshot = library
        let idMapSnapshot = idMap
        let trackCount = library.tracks.count
        let expectedDate = xmlLoadedModificationDate
        statusMessage = "Writing XML..."
        isWritingXML = true

        Task.detached(priority: .userInitiated) {
            let fm = FileManager.default

            // Re-check right before writing — the main-actor check above races
            // with this detached write
            let diskDate = (try? fm.attributesOfItem(atPath: xmlPath))?[.modificationDate] as? Date
            if let expectedDate, let diskDate, diskDate != expectedDate {
                await MainActor.run {
                    self.errorMessage = "XML file changed on disk during sync. Refresh and try again."
                    self.statusMessage = ""
                    self.isWritingXML = false
                }
                return
            }

            do {
                let data = try RekordboxXMLWriter.write(library: librarySnapshot)

                // Back up the existing XML before overwriting it
                if fm.fileExists(atPath: xmlPath) {
                    let stamp = backupFormatter.string(from: Date())
                    try fm.copyItem(
                        at: URL(fileURLWithPath: xmlPath),
                        to: URL(fileURLWithPath: "\(xmlPath).\(stamp).bak")
                    )
                    pruneBackups(xmlPath: xmlPath)
                }

                // idMap first: it's recoverable via seeding, the XML is not
                try idMapSnapshot.save(to: AppSettings.trackIDMapURL)
                try data.write(to: URL(fileURLWithPath: xmlPath), options: .atomic)
                let newDate = (try? fm.attributesOfItem(atPath: xmlPath))?[.modificationDate] as? Date

                await MainActor.run {
                    self.xmlLoadedModificationDate = newDate
                    // Create an empty diff to keep showing folder structure
                    self.diff = SyncDiff(
                        newTracks: [],
                        removedTracks: [],
                        unchangedCount: trackCount,
                        scannedFolders: self.scannedFolders
                    )
                    self.removalSelections = []
                    self.syncSuccess = true
                    self.statusMessage = "Synced! Library now has \(trackCount) tracks."
                    self.isWritingXML = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Sync failed: \(error.localizedDescription)"
                    self.statusMessage = "Sync failed. Refresh to reload the library."
                    self.isWritingXML = false
                }
            }
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
        let filteredFilePaths = Set(filteredFolders.flatMap { $0.allFiles }.map { $0.path })
        return diff!.newTracks.filter { filteredFilePaths.contains($0.path) }.count
    }

    var selectedFolderCount: Int {
        selectedFolders.count
    }
}

private let backupFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyyMMdd-HHmmss"
    return f
}()

/// Keep only the newest `keep` timestamped backups of the XML file.
private func pruneBackups(xmlPath: String, keep: Int = 5) {
    let fm = FileManager.default
    let url = URL(fileURLWithPath: xmlPath)
    let dir = url.deletingLastPathComponent()
    let prefix = url.lastPathComponent + "."
    guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
    // Match only our own stamp pattern so a user's hand-made .bak files survive
    let backups = names.filter {
        $0.hasPrefix(prefix) && $0.range(of: #"\.\d{8}-\d{6}\.bak$"#, options: .regularExpression) != nil
    }.sorted()
    for name in backups.dropLast(keep) {
        try? fm.removeItem(at: dir.appendingPathComponent(name))
    }
}
