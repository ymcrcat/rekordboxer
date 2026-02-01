import Foundation

public struct USBSyncPlan {
    public struct FileCopy {
        public let source: URL
        public let destination: URL
        public let filename: String
    }

    public let filesToCopy: [FileCopy]
    public let usbRoot: URL

    public init(filesToCopy: [FileCopy], usbRoot: URL) {
        self.filesToCopy = filesToCopy
        self.usbRoot = usbRoot
    }
}

public enum USBSync {
    public static func plan(tracks: [Track], usbRoot: URL) throws -> USBSyncPlan {
        let fm = FileManager.default
        var copies: [USBSyncPlan.FileCopy] = []

        // Build an index of all files already on the USB so we can find
        // where rekordbox placed each track (typically Contents/Artist/Album/file)
        let contentsDir = usbRoot.appendingPathComponent("Contents")
        let usbFileIndex: [String: URL]
        if fm.fileExists(atPath: contentsDir.path) {
            usbFileIndex = try buildFileIndex(root: contentsDir)
        } else {
            usbFileIndex = try buildFileIndex(root: usbRoot)
        }

        for track in tracks {
            let sourcePath = track.filePath
            let sourceURL = URL(fileURLWithPath: sourcePath)
            let filename = sourceURL.lastPathComponent

            guard fm.fileExists(atPath: sourcePath) else { continue }

            // Find existing file on USB by filename
            guard let existingUSBPath = usbFileIndex[filename] else { continue }

            let sourceAttrs = try fm.attributesOfItem(atPath: sourcePath)
            let sourceSize = (sourceAttrs[.size] as? Int64) ?? 0

            let usbAttrs = try fm.attributesOfItem(atPath: existingUSBPath.path)
            let usbSize = (usbAttrs[.size] as? Int64) ?? -1

            if usbSize == sourceSize { continue }

            copies.append(USBSyncPlan.FileCopy(source: sourceURL, destination: existingUSBPath, filename: filename))
        }

        return USBSyncPlan(filesToCopy: copies, usbRoot: usbRoot)
    }

    public static func execute(plan: USBSyncPlan) throws {
        let fm = FileManager.default

        for copy in plan.filesToCopy {
            if fm.fileExists(atPath: copy.destination.path) {
                try fm.removeItem(at: copy.destination)
            }
            try fm.copyItem(at: copy.source, to: copy.destination)
        }
    }

    /// Build an index of filenames to their paths within a directory tree.
    private static func buildFileIndex(root: URL) throws -> [String: URL] {
        let fm = FileManager.default
        var index: [String: URL] = [:]
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return index
        }
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                index[fileURL.lastPathComponent] = fileURL
            }
        }
        return index
    }
}
