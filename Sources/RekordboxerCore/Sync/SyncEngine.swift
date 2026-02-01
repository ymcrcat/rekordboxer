import Foundation

public struct SyncDiff {
    public let newTracks: [ScannedFile]
    public let removedTracks: [Track]
    public let unchangedCount: Int
    public let playlistMapping: [(playlistName: String, fileURLs: [URL])]

    public init(newTracks: [ScannedFile], removedTracks: [Track], unchangedCount: Int, playlistMapping: [(playlistName: String, fileURLs: [URL])]) {
        self.newTracks = newTracks
        self.removedTracks = removedTracks
        self.unchangedCount = unchangedCount
        self.playlistMapping = playlistMapping
    }
}

public enum SyncEngine {
    public static func diff(library: RekordboxLibrary, scannedFolders: [ScannedFolder]) -> SyncDiff {
        var existingPaths: Set<String> = []
        for track in library.tracks.values {
            existingPaths.insert(track.filePath)
        }

        var scannedPaths: Set<String> = []
        var newFiles: [ScannedFile] = []
        var playlistMapping: [(String, [URL])] = []

        for folder in scannedFolders {
            var folderURLs: [URL] = []
            for file in folder.files {
                let path = file.url.path
                scannedPaths.insert(path)
                folderURLs.append(file.url)
                if !existingPaths.contains(path) {
                    newFiles.append(file)
                }
            }
            playlistMapping.append((folder.folderName, folderURLs))
        }

        let removedTracks = library.tracks.values.filter { track in
            !scannedPaths.contains(track.filePath)
        }.sorted { $0.trackID < $1.trackID }

        let unchangedCount = existingPaths.intersection(scannedPaths).count

        return SyncDiff(
            newTracks: newFiles,
            removedTracks: removedTracks,
            unchangedCount: unchangedCount,
            playlistMapping: playlistMapping
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

        var playlistNodes: [PlaylistNode] = []
        for (playlistName, fileURLs) in diff.playlistMapping {
            let trackKeys = fileURLs.compactMap { url -> Int? in
                idMap.trackID(for: url.path)
            }
            if !trackKeys.isEmpty {
                playlistNodes.append(PlaylistNode(
                    type: .playlist,
                    name: playlistName,
                    children: [],
                    trackKeys: trackKeys
                ))
            }
        }
        library.rootNode = PlaylistNode(type: .folder, name: "ROOT", children: playlistNodes, trackKeys: [])
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
