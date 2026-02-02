import Foundation
import RekordboxerCore

@MainActor
final class USBSyncViewModel: ObservableObject {
    @Published var mountedVolumes: [URL] = []
    @Published var selectedVolume: URL?
    @Published var selectedPlaylists: Set<String> = []
    @Published var playlistNodes: [PlaylistNode] = []
    @Published var plan: USBSyncPlan?
    @Published var copySelections: Set<String> = []
    @Published var isSyncing: Bool = false
    @Published var statusMessage: String = ""
    @Published var errorMessage: String?
    @Published var syncProgress: Double = 0
    @Published var syncCurrentFile: String = ""

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
            playlistNodes = library.rootNode.children
            statusMessage = "Library loaded: \(library.tracks.count) tracks"
        } catch {
            errorMessage = "Failed to load XML: \(error.localizedDescription)"
        }
    }

    // MARK: - Playlist Selection

    func toggleNode(_ node: PlaylistNode, prefix: String) {
        let paths = allPlaylistPaths(node: node, prefix: prefix)
        if checkState(for: node, prefix: prefix) == .checked {
            selectedPlaylists.subtract(paths)
        } else {
            selectedPlaylists.formUnion(paths)
        }
    }

    func checkState(for node: PlaylistNode, prefix: String) -> CheckState {
        let path = prefix.isEmpty ? node.name : "\(prefix)/\(node.name)"
        if node.isPlaylist {
            return selectedPlaylists.contains(path) ? .checked : .unchecked
        }
        let paths = allPlaylistPaths(node: node, prefix: prefix)
        if paths.isEmpty { return .unchecked }
        let selectedCount = paths.filter { selectedPlaylists.contains($0) }.count
        if selectedCount == 0 {
            return .unchecked
        } else if selectedCount == paths.count {
            return .checked
        } else {
            return .mixed
        }
    }

    func allPlaylistPaths(node: PlaylistNode, prefix: String) -> Set<String> {
        let path = prefix.isEmpty ? node.name : "\(prefix)/\(node.name)"
        if node.isPlaylist {
            return [path]
        }
        var result = Set<String>()
        for child in node.children {
            result.formUnion(allPlaylistPaths(node: child, prefix: path))
        }
        return result
    }

    // MARK: - Volumes

    func refreshVolumes() {
        let fm = FileManager.default
        let volumesURL = URL(fileURLWithPath: "/Volumes")
        do {
            let contents = try fm.contentsOfDirectory(at: volumesURL, includingPropertiesForKeys: [.volumeIsRemovableKey, .volumeIsInternalKey])
            mountedVolumes = contents.filter { url in
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

    // MARK: - Plan & Sync

    func planSync() {
        errorMessage = nil
        plan = nil
        copySelections = []

        guard let volume = selectedVolume else {
            errorMessage = "No volume selected."
            return
        }

        guard !selectedPlaylists.isEmpty else {
            errorMessage = "No playlists selected."
            return
        }

        var trackKeys: [Int] = []
        for child in library.rootNode.children {
            collectTrackKeys(node: child, prefix: "", selectedPaths: selectedPlaylists, into: &trackKeys)
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
        syncProgress = 0
        syncCurrentFile = ""
        statusMessage = "Copying files..."

        Task.detached { [filteredPlan] in
            do {
                try USBSync.execute(plan: filteredPlan) { completed, total, filename in
                    Task { @MainActor in
                        self.syncProgress = Double(completed) / Double(total)
                        self.syncCurrentFile = filename
                        if completed < total {
                            self.statusMessage = "Copying \(completed + 1) of \(total): \(filename)"
                        }
                    }
                }
                await MainActor.run {
                    self.plan = nil
                    self.copySelections = []
                    self.statusMessage = "USB sync complete! Copied \(filteredPlan.filesToCopy.count) files."
                    self.isSyncing = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Sync failed: \(error.localizedDescription)"
                    self.isSyncing = false
                }
            }
        }
    }
}
