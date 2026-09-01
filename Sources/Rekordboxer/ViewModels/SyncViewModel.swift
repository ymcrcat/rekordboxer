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
            xmlLoadedModificationDate = LibraryBackup.modificationDate(of: xmlPath)
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
                        ? FolderSelection.allPaths(in: folders)
                        : FolderSelection.preselect(in: folders, existingPaths: existingPaths.union(newTrackPaths))
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
        let paths = FolderSelection.allPaths(in: [folder])
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
        FolderSelection.checkState(for: folder, selected: selectedFolders)
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

        // Refuse to overwrite edits made to the XML since the last scan
        let currentDate = LibraryBackup.modificationDate(of: xmlPath)
        if let stale = LibraryBackup.staleness(loaded: xmlLoadedModificationDate, current: currentDate) {
            errorMessage = stale.message
            return
        }

        let filteredFolders = FolderSelection.filter(scannedFolders, selectedPaths: selectedFolders)
        let filteredFiles = filteredFolders.flatMap { $0.allFiles }
        let filteredFilePaths = Set(filteredFiles.map { $0.path })
        let filteredNewTracks = diff.newTracks.filter { filteredFilePaths.contains($0.path) }

        // Remove existing tracks that belong to unselected folders
        let removals = FolderSelection.removals(
            userSelected: removalSelections,
            library: library,
            allScannedPaths: Set(scannedFolders.flatMap { $0.allFiles }.map { $0.path }),
            selectedPaths: filteredFilePaths
        )

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
            let diskDate = LibraryBackup.modificationDate(of: xmlPath)
            if LibraryBackup.staleness(loaded: expectedDate, current: diskDate) != nil {
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
                try LibraryBackup.backup(xmlPath: xmlPath)

                // idMap first: it's recoverable via seeding, the XML is not
                try idMapSnapshot.save(to: AppSettings.trackIDMapURL)
                try data.write(to: URL(fileURLWithPath: xmlPath), options: .atomic)
                let newDate = LibraryBackup.modificationDate(of: xmlPath)

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

    var selectedNewTrackCount: Int {
        guard diff != nil else { return 0 }
        let filteredFolders = FolderSelection.filter(scannedFolders, selectedPaths: selectedFolders)
        let filteredFilePaths = Set(filteredFolders.flatMap { $0.allFiles }.map { $0.path })
        return diff!.newTracks.filter { filteredFilePaths.contains($0.path) }.count
    }

    var selectedFolderCount: Int {
        selectedFolders.count
    }
}
