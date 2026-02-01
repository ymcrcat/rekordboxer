import Foundation

public struct ScannedFolder {
    public let folderName: String
    public let folderURL: URL
    public let files: [ScannedFile]       // audio files directly in this folder
    public let children: [ScannedFolder]  // subfolders

    public init(folderName: String, folderURL: URL, files: [ScannedFile], children: [ScannedFolder]) {
        self.folderName = folderName
        self.folderURL = folderURL
        self.files = files
        self.children = children
    }

    /// All audio files in this folder and all descendants.
    public var allFiles: [ScannedFile] {
        files + children.flatMap { $0.allFiles }
    }
}

public struct ScannedFile {
    public let url: URL
    public let size: Int64
    public let modificationDate: Date
}

public enum FolderScanner {
    public static let audioExtensions: Set<String> = ["mp3", "wav", "flac", "aiff", "aif", "aac", "m4a", "ogg", "alac"]

    /// Scan root directory and return its children as a list of ScannedFolder trees.
    /// Audio files directly in root are returned as a ScannedFolder named after the root.
    public static func scan(root: URL) throws -> [ScannedFolder] {
        let fm = FileManager.default
        var results: [ScannedFolder] = []

        // Pick up audio files directly in root
        let rootFiles = try scanAudioFilesFlat(in: root)
        if !rootFiles.isEmpty {
            results.append(ScannedFolder(folderName: root.lastPathComponent, folderURL: root, files: rootFiles, children: []))
        }

        // Scan each subdirectory as a tree
        let contents = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        let subdirs = contents.filter { url in
            var isDir: ObjCBool = false
            fm.fileExists(atPath: url.path, isDirectory: &isDir)
            return isDir.boolValue
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        for subdir in subdirs {
            if let folder = try scanFolderTree(at: subdir) {
                results.append(folder)
            }
        }

        return results
    }

    /// Recursively scan a directory into a ScannedFolder tree.
    /// Returns nil if the folder and all its descendants contain no audio files.
    private static func scanFolderTree(at directory: URL) throws -> ScannedFolder? {
        let fm = FileManager.default
        let files = try scanAudioFilesFlat(in: directory)

        let contents = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let subdirs = contents.filter { url in
            var isDir: ObjCBool = false
            fm.fileExists(atPath: url.path, isDirectory: &isDir)
            return isDir.boolValue
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        var children: [ScannedFolder] = []
        for subdir in subdirs {
            if let child = try scanFolderTree(at: subdir) {
                children.append(child)
            }
        }

        guard !files.isEmpty || !children.isEmpty else { return nil }

        return ScannedFolder(
            folderName: directory.lastPathComponent,
            folderURL: directory,
            files: files,
            children: children
        )
    }

    /// Scan a single directory for audio files (non-recursive).
    private static func scanAudioFilesFlat(in directory: URL) throws -> [ScannedFile] {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])

        return contents.compactMap { url in
            guard audioExtensions.contains(url.pathExtension.lowercased()) else { return nil }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return ScannedFile(
                url: url,
                size: Int64(values?.fileSize ?? 0),
                modificationDate: values?.contentModificationDate ?? Date()
            )
        }.sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
    }
}
