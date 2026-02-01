import Foundation
import RekordboxerCore

@MainActor
final class USBSyncViewModel: ObservableObject {
    @Published var mountedVolumes: [URL] = []
    @Published var selectedVolume: URL?
    @Published var playlistSelections: [String: Bool] = [:]
    @Published var plan: USBSyncPlan?
    @Published var isSyncing: Bool = false
    @Published var statusMessage: String = ""
    @Published var errorMessage: String?

    private var settings = AppSettings()
    private var library = RekordboxLibrary()

    func loadOnAppear() {
        do {
            settings = try AppSettings.load(from: AppSettings.defaultURL)
        } catch {
            settings = AppSettings()
        }

        loadLibrary()
        refreshVolumes()
    }

    private func loadLibrary() {
        let xmlPath = settings.xmlFilePath
        guard !xmlPath.isEmpty else {
            statusMessage = "No XML file configured. Go to Settings."
            return
        }

        let url = URL(fileURLWithPath: xmlPath)
        guard FileManager.default.fileExists(atPath: xmlPath) else {
            statusMessage = "XML file not found. Run Library Sync first."
            return
        }

        do {
            let data = try Data(contentsOf: url)
            library = try RekordboxXMLParser.parse(data: data)
            loadPlaylists()
            statusMessage = "Library loaded: \(library.tracks.count) tracks"
        } catch {
            errorMessage = "Failed to load XML: \(error.localizedDescription)"
        }
    }

    private func loadPlaylists() {
        playlistSelections = [:]
        for child in library.rootNode.children where child.isPlaylist {
            playlistSelections[child.name] = false
        }
    }

    func refreshVolumes() {
        let fm = FileManager.default
        let volumesURL = URL(fileURLWithPath: "/Volumes")
        do {
            let contents = try fm.contentsOfDirectory(at: volumesURL, includingPropertiesForKeys: nil)
            mountedVolumes = contents.sorted { $0.lastPathComponent < $1.lastPathComponent }
            if selectedVolume == nil, let first = mountedVolumes.first {
                selectedVolume = first
            }
        } catch {
            errorMessage = "Failed to list volumes: \(error.localizedDescription)"
        }
    }

    func planSync() {
        errorMessage = nil
        plan = nil

        guard let volume = selectedVolume else {
            errorMessage = "No volume selected."
            return
        }

        let selectedPlaylistNames = playlistSelections.filter { $0.value }.map { $0.key }
        guard !selectedPlaylistNames.isEmpty else {
            errorMessage = "No playlists selected."
            return
        }

        let selectedNames = Set(selectedPlaylistNames)
        var tracks: [Track] = []
        for child in library.rootNode.children where child.isPlaylist && selectedNames.contains(child.name) {
            for key in child.trackKeys {
                if let track = library.tracks[key] {
                    tracks.append(track)
                }
            }
        }

        do {
            let manifest = try USBManifest.load(from: volume.appendingPathComponent(".rekordboxer_manifest.json"))
            let result = try USBSync.plan(tracks: tracks, usbRoot: volume, manifest: manifest)
            self.plan = result
            statusMessage = "\(result.filesToCopy.count) files to copy"
        } catch {
            errorMessage = "Plan failed: \(error.localizedDescription)"
        }
    }

    func executeSync() {
        guard let plan = plan else { return }
        errorMessage = nil
        isSyncing = true
        statusMessage = "Copying files..."

        Task {
            do {
                let manifest = try USBSync.execute(plan: plan)
                try manifest.save(to: plan.usbRoot.appendingPathComponent(".rekordboxer_manifest.json"))
                self.plan = nil
                self.statusMessage = "USB sync complete! Copied \(plan.filesToCopy.count) files."
            } catch {
                self.errorMessage = "Sync failed: \(error.localizedDescription)"
            }
            self.isSyncing = false
        }
    }
}
