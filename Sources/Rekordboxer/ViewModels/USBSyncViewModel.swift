import Foundation
import RekordboxerCore

@MainActor
final class USBSyncViewModel: ObservableObject {
    @Published var mountedVolumes: [URL] = []
    @Published var selectedVolume: URL?
    @Published var playlistSelections: [String: Bool] = [:]
    @Published var plan: USBSyncPlan?
    @Published var copySelections: Set<String> = []
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
        for child in library.rootNode.children {
            collectPlaylists(node: child, prefix: "")
        }
    }

    private func collectPlaylists(node: PlaylistNode, prefix: String) {
        let path = prefix.isEmpty ? node.name : "\(prefix)/\(node.name)"
        if node.isPlaylist {
            playlistSelections[path] = false
        } else {
            for child in node.children {
                collectPlaylists(node: child, prefix: path)
            }
        }
    }

    func refreshVolumes() {
        let fm = FileManager.default
        let volumesURL = URL(fileURLWithPath: "/Volumes")
        do {
            let contents = try fm.contentsOfDirectory(at: volumesURL, includingPropertiesForKeys: [.volumeIsRemovableKey, .volumeIsInternalKey])
            mountedVolumes = contents.filter { url in
                // Filter out internal/boot volumes — only show removable or external drives
                guard let values = try? url.resourceValues(forKeys: [.volumeIsRemovableKey, .volumeIsInternalKey]) else {
                    return false
                }
                let isRemovable = values.volumeIsRemovable ?? false
                let isInternal = values.volumeIsInternal ?? true
                return isRemovable || !isInternal
            }.sorted { $0.lastPathComponent < $1.lastPathComponent }
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
        copySelections = []

        guard let volume = selectedVolume else {
            errorMessage = "No volume selected."
            return
        }

        let selectedPlaylistNames = playlistSelections.filter { $0.value }.map { $0.key }
        guard !selectedPlaylistNames.isEmpty else {
            errorMessage = "No playlists selected."
            return
        }

        let selectedPaths = Set(selectedPlaylistNames)
        var trackKeys: [Int] = []
        for child in library.rootNode.children {
            collectTrackKeys(node: child, prefix: "", selectedPaths: selectedPaths, into: &trackKeys)
        }
        let seen = NSMutableSet()
        let tracks = trackKeys.compactMap { key -> Track? in
            guard !seen.contains(key), let track = library.tracks[key] else { return nil }
            seen.add(key)
            return track
        }

        do {
            let result = try USBSync.plan(tracks: tracks, usbRoot: volume)
            self.plan = result
            statusMessage = "\(result.filesToCopy.count) files to copy"
        } catch {
            errorMessage = "Plan failed: \(error.localizedDescription)"
        }
    }

    private func collectTrackKeys(node: PlaylistNode, prefix: String, selectedPaths: Set<String>, into keys: inout [Int]) {
        let path = prefix.isEmpty ? node.name : "\(prefix)/\(node.name)"
        if node.isPlaylist {
            if selectedPaths.contains(path) {
                keys.append(contentsOf: node.trackKeys)
            }
        } else {
            for child in node.children {
                collectTrackKeys(node: child, prefix: path, selectedPaths: selectedPaths, into: &keys)
            }
        }
    }

    func executeSync() {
        guard let plan = plan else { return }
        let selectedFiles = plan.filesToCopy.filter { copySelections.contains($0.filename) }
        guard !selectedFiles.isEmpty else {
            errorMessage = "No files selected to copy."
            return
        }
        let filteredPlan = USBSyncPlan(filesToCopy: selectedFiles, usbRoot: plan.usbRoot)

        errorMessage = nil
        isSyncing = true
        statusMessage = "Copying files..."

        Task {
            do {
                try USBSync.execute(plan: filteredPlan)
                self.plan = nil
                self.copySelections = []
                self.statusMessage = "USB sync complete! Copied \(filteredPlan.filesToCopy.count) files."
            } catch {
                self.errorMessage = "Sync failed: \(error.localizedDescription)"
            }
            self.isSyncing = false
        }
    }
}
