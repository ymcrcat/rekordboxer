import Foundation

public struct SyncDiff {
    public let newTracks: [ScannedFile]
    public let removedTracks: [Track]
    public let unchangedCount: Int
    public let scannedFolders: [ScannedFolder]

    public init(newTracks: [ScannedFile], removedTracks: [Track], unchangedCount: Int, scannedFolders: [ScannedFolder]) {
        self.newTracks = newTracks
        self.removedTracks = removedTracks
        self.unchangedCount = unchangedCount
        self.scannedFolders = scannedFolders
    }
}

public enum SyncEngine {
    public static func diff(library: RekordboxLibrary, scannedFolders: [ScannedFolder]) -> SyncDiff {
        var existingPaths: Set<String> = []
        for track in library.tracks.values {
            existingPaths.insert(track.filePath)
        }

        // Collect all scanned file paths and detect new files
        let allFiles = scannedFolders.flatMap { $0.allFiles }
        var scannedPaths: Set<String> = []
        var newFiles: [ScannedFile] = []

        for file in allFiles {
            let path = file.url.path
            scannedPaths.insert(path)
            if !existingPaths.contains(path) {
                newFiles.append(file)
            }
        }

        let removedTracks = library.tracks.values.filter { track in
            !scannedPaths.contains(track.filePath)
        }.sorted { $0.trackID < $1.trackID }

        let unchangedCount = existingPaths.intersection(scannedPaths).count

        return SyncDiff(
            newTracks: newFiles,
            removedTracks: removedTracks,
            unchangedCount: unchangedCount,
            scannedFolders: scannedFolders
        )
    }

    public static func apply(diff: SyncDiff, to library: inout RekordboxLibrary, idMap: inout TrackIDMap, removals: Set<Int>) {
        for trackID in removals {
            if let track = library.tracks[trackID] {
                idMap.remove(path: track.filePath)
                library.tracks.removeValue(forKey: trackID)
            }
        }

        for file in diff.newTracks {
            let path = file.url.path
            let trackID = idMap.getOrAssign(path: path)
            var track = Track(trackID: trackID)
            track.name = file.url.deletingPathExtension().lastPathComponent
            track.location = Track.encodeLocation(path)
            track.size = file.size
            track.kind = audioKind(for: file.url.pathExtension)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            track.dateAdded = formatter.string(from: Date())
            library.tracks[trackID] = track
        }

        // Build nested playlist tree mirroring the folder structure
        let children = diff.scannedFolders.compactMap { folder in
            buildPlaylistNode(from: folder, idMap: idMap)
        }
        library.rootNode = PlaylistNode(type: .folder, name: "ROOT", children: children, trackKeys: [])
    }

    /// Recursively convert a ScannedFolder tree into a PlaylistNode tree.
    /// - Folders with only subfolders become playlist folders
    /// - Folders with audio files become playlists (containing those files)
    /// - Folders with both get a playlist for their files plus child folders
    private static func buildPlaylistNode(from folder: ScannedFolder, idMap: TrackIDMap) -> PlaylistNode? {
        let directTrackKeys = folder.files.compactMap { file -> Int? in
            idMap.trackID(for: file.url.path)
        }

        let childNodes = folder.children.compactMap { child in
            buildPlaylistNode(from: child, idMap: idMap)
        }

        // No files and no children with files — skip
        if directTrackKeys.isEmpty && childNodes.isEmpty {
            return nil
        }

        // Leaf folder (has files, no subfolders) — make a playlist
        if childNodes.isEmpty {
            return PlaylistNode(type: .playlist, name: folder.folderName, children: [], trackKeys: directTrackKeys)
        }

        // Has subfolders — make a folder node
        var children = childNodes

        // If this folder also has direct audio files, add a playlist for them
        if !directTrackKeys.isEmpty {
            children.insert(PlaylistNode(
                type: .playlist,
                name: folder.folderName,
                children: [],
                trackKeys: directTrackKeys
            ), at: 0)
        }

        return PlaylistNode(type: .folder, name: folder.folderName, children: children, trackKeys: [])
    }

    private static func audioKind(for ext: String) -> String {
        switch ext.lowercased() {
        case "mp3": return "MP3 File"
        case "wav": return "WAV File"
        case "flac": return "FLAC File"
        case "aiff", "aif": return "AIFF File"
        case "aac", "m4a": return "AAC File"
        case "ogg": return "OGG File"
        default: return "Audio File"
        }
    }
}
