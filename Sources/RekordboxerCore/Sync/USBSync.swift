import Foundation

public struct USBSyncPlan {
    public struct FileCopy {
        public let source: URL
        public let destination: URL
        public let filename: String
    }

    public let filesToCopy: [FileCopy]
    public let skippedAmbiguous: [String]
    public let usbRoot: URL

    public init(filesToCopy: [FileCopy], skippedAmbiguous: [String] = [], usbRoot: URL) {
        self.filesToCopy = filesToCopy
        self.skippedAmbiguous = skippedAmbiguous
        self.usbRoot = usbRoot
    }
}

public enum USBSync {
    public static func plan(tracks: [Track], usbRoot: URL) throws -> USBSyncPlan {
        let fm = FileManager.default
        var copies: [USBSyncPlan.FileCopy] = []
        var skippedAmbiguous: [String] = []

        // Build an index of all files already on the USB so we can find
        // where rekordbox placed each track (typically Contents/Artist/Album/file)
        let contentsDir = usbRoot.appendingPathComponent("Contents")
        let searchRoot = fm.fileExists(atPath: contentsDir.path) ? contentsDir : usbRoot
        let usbFileIndex = try buildFileIndex(root: searchRoot)

        for track in tracks {
            let sourcePath = track.filePath
            let sourceURL = URL(fileURLWithPath: sourcePath)
            let filename = sourceURL.lastPathComponent

            guard fm.fileExists(atPath: sourcePath) else { continue }

            // Find existing file on USB by filename
            guard let usbMatches = usbFileIndex[filename] else { continue }

            // Skip ambiguous matches — two USB files with the same name would risk overwriting the wrong one
            if usbMatches.count > 1 {
                skippedAmbiguous.append(filename)
                continue
            }
            let existingUSBPath = usbMatches[0]

            let sourceAttrs = try fm.attributesOfItem(atPath: sourcePath)
            let sourceSize = (sourceAttrs[.size] as? Int64) ?? 0

            let usbAttrs = try fm.attributesOfItem(atPath: existingUSBPath.path)
            let usbSize = (usbAttrs[.size] as? Int64) ?? -1

            if usbSize == sourceSize { continue }

            copies.append(USBSyncPlan.FileCopy(source: sourceURL, destination: existingUSBPath, filename: filename))
        }

        return USBSyncPlan(filesToCopy: copies, skippedAmbiguous: skippedAmbiguous, usbRoot: usbRoot)
    }

    public static func execute(plan: USBSyncPlan, progress: ((Int, Int, String) -> Void)? = nil) throws {
        let fm = FileManager.default
        let total = plan.filesToCopy.count

        for (index, copy) in plan.filesToCopy.enumerated() {
            progress?(index, total, copy.filename)
            if fm.fileExists(atPath: copy.destination.path) {
                try fm.removeItem(at: copy.destination)
            }
            try fm.copyItem(at: copy.source, to: copy.destination)
        }
        progress?(total, total, "")
    }

    /// Build an index of filenames to all matching paths within a directory tree.
    /// Multiple paths per filename are retained so callers can detect ambiguous matches.
    private static func buildFileIndex(root: URL) throws -> [String: [URL]] {
        let fm = FileManager.default
        var index: [String: [URL]] = [:]
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return index
        }
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                index[fileURL.lastPathComponent, default: []].append(fileURL)
            }
        }
        return index
    }
}
