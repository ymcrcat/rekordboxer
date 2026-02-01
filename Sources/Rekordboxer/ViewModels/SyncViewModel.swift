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
                self.removalSelections = Set(result.removedTracks.map { $0.trackID })
                self.statusMessage = "\(result.newTracks.count) new, \(result.removedTracks.count) removed, \(result.unchangedCount) unchanged"
            } catch {
                self.errorMessage = "Scan failed: \(error.localizedDescription)"
            }
            self.isScanning = false
        }
    }

    func syncToXML() {
        guard let diff = diff else { return }
        errorMessage = nil

        do {
            SyncEngine.apply(diff: diff, to: &library, idMap: &idMap, removals: removalSelections)

            let xmlPath = settings.xmlFilePath
            guard !xmlPath.isEmpty else {
                errorMessage = "No XML file path configured."
                return
            }

            let data = try RekordboxXMLWriter.write(library: library)
            try data.write(to: URL(fileURLWithPath: xmlPath))
            try idMap.save(to: AppSettings.trackIDMapURL)

            self.diff = nil
            self.removalSelections = []
            statusMessage = "Synced! Library now has \(library.tracks.count) tracks."
        } catch {
            errorMessage = "Sync failed: \(error.localizedDescription)"
        }
    }
}
