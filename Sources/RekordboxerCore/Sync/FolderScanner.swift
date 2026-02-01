import Foundation

public struct ScannedFolder {
    public let folderName: String
    public let folderURL: URL
    public let files: [ScannedFile]
}

public struct ScannedFile {
    public let url: URL
    public let size: Int64
    public let modificationDate: Date
}

public enum FolderScanner {
    public static let audioExtensions: Set<String> = ["mp3", "wav", "flac", "aiff", "aif", "aac", "m4a", "ogg", "alac"]

    public static func scan(root: URL) throws -> [ScannedFolder] {
        let fm = FileManager.default
        var folders: [ScannedFolder] = []

        let contents = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        let subdirs = contents.filter { url in
            var isDir: ObjCBool = false
            fm.fileExists(atPath: url.path, isDirectory: &isDir)
            return isDir.boolValue
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        for subdir in subdirs {
            let files = try scanAudioFiles(in: subdir)
            if !files.isEmpty {
                folders.append(ScannedFolder(
                    folderName: subdir.lastPathComponent,
                    folderURL: subdir,
                    files: files
                ))
            }
        }

        return folders
    }

    private static func scanAudioFiles(in directory: URL) throws -> [ScannedFile] {
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
