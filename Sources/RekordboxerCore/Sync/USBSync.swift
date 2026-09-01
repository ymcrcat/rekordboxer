import Foundation

public struct USBSyncPlan {
    public struct FileCopy {
        public let source: URL
        public let destination: URL
        public let filename: String
    }

    public let filesToCopy: [FileCopy]
    public let skippedAmbiguous: [String]
    public let notOnUSB: [String]
    public let sourceMissing: [String]
    public let usbRoot: URL

    public init(filesToCopy: [FileCopy], skippedAmbiguous: [String] = [], notOnUSB: [String] = [], sourceMissing: [String] = [], usbRoot: URL) {
        self.filesToCopy = filesToCopy
        self.skippedAmbiguous = skippedAmbiguous
        self.notOnUSB = notOnUSB
        self.sourceMissing = sourceMissing
        self.usbRoot = usbRoot
    }
}

public enum USBSync {
    /// - Parameter allTracks: full library used for duplicate-filename ambiguity
    ///   detection. Ambiguity must consider the whole library, not just the
    ///   selected tracks — an unselected track sharing a filename would otherwise
    ///   be silently overwritten on the USB. Defaults to `tracks`.
    public static func plan(tracks: [Track], allTracks: [Track]? = nil, usbRoot: URL) throws -> USBSyncPlan {
        let fm = FileManager.default
        var copies: [USBSyncPlan.FileCopy] = []
        var skippedAmbiguous: [String] = []
        var notOnUSB: [String] = []
        var sourceMissing: [String] = []

        // Build an index of all files already on the USB so we can find
        // where rekordbox placed each track (typically Contents/Artist/Album/file)
        let contentsDir = usbRoot.appendingPathComponent("Contents")
        let searchRoot = fm.fileExists(atPath: contentsDir.path) ? contentsDir : usbRoot
        let usbFileIndex = try buildFileIndex(root: searchRoot)

        // Two source tracks with the same filename would both target the same
        // USB file — last write wins silently. Treat those as ambiguous too.
        var sourceNameCounts: [String: Int] = [:]
        for track in (allTracks ?? tracks) {
            let name = URL(fileURLWithPath: track.filePath).lastPathComponent.precomposedStringWithCanonicalMapping
            sourceNameCounts[name, default: 0] += 1
        }

        for track in tracks {
            let sourcePath = track.filePath
            let sourceURL = URL(fileURLWithPath: sourcePath)
            let filename = sourceURL.lastPathComponent.precomposedStringWithCanonicalMapping

            guard fm.fileExists(atPath: sourcePath) else {
                sourceMissing.append(filename)
                continue
            }

            // Find existing file on USB by filename
            guard let usbMatches = usbFileIndex[filename] else {
                notOnUSB.append(filename)
                continue
            }

            // Skip ambiguous matches — same name twice on the USB, or twice in
            // the source, would risk overwriting the wrong file
            if usbMatches.count > 1 || sourceNameCounts[filename, default: 0] > 1 {
                if !skippedAmbiguous.contains(filename) {
                    skippedAmbiguous.append(filename)
                }
                continue
            }
            let existingUSBPath = usbMatches[0]

            // Attribute reads can fail if a file vanishes mid-plan; degrade per
            // file instead of aborting the whole plan
            let sourceAttrs = try? fm.attributesOfItem(atPath: sourcePath)
            let usbAttrs = try? fm.attributesOfItem(atPath: existingUSBPath.path)
            let sourceSize = (sourceAttrs?[.size] as? Int64) ?? 0
            let usbSize = (usbAttrs?[.size] as? Int64) ?? -1

            if usbSize == sourceSize {
                // Same size: fall back to mtime so same-size edits still sync.
                // copyItem preserves the source mtime, and FAT stores it at 2s
                // granularity — copy only if the source is clearly newer.
                let sourceDate = (sourceAttrs?[.modificationDate] as? Date) ?? .distantPast
                let usbDate = (usbAttrs?[.modificationDate] as? Date) ?? .distantPast
                // abs(): FAT stores local time, so a DST/timezone shift moves every
                // USB mtime by whole hours — either direction means "differs, recopy"
                // (safe), never "skip an edited file"
                if abs(sourceDate.timeIntervalSince(usbDate)) <= 2 { continue }
            }

            copies.append(USBSyncPlan.FileCopy(source: sourceURL, destination: existingUSBPath, filename: filename))
        }

        return USBSyncPlan(filesToCopy: copies, skippedAmbiguous: skippedAmbiguous, notOnUSB: notOnUSB, sourceMissing: sourceMissing, usbRoot: usbRoot)
    }

    public static func execute(plan: USBSyncPlan, progress: ((Int, Int, String) -> Void)? = nil) throws {
        let fm = FileManager.default
        let total = plan.filesToCopy.count

        for (index, copy) in plan.filesToCopy.enumerated() {
            progress?(index, total, copy.filename)
            // Copy to a hidden temp file first, then swap — deleting the
            // destination before a full copy would lose it if the copy fails
            let tempURL = copy.destination.deletingLastPathComponent()
                .appendingPathComponent(".rekordboxer-tmp-\(copy.filename)")
            try? fm.removeItem(at: tempURL)
            do {
                try fm.copyItem(at: copy.source, to: tempURL)
                if fm.fileExists(atPath: copy.destination.path) {
                    try fm.removeItem(at: copy.destination)
                }
                try fm.moveItem(at: tempURL, to: copy.destination)
            } catch {
                // If the destination was already removed, the temp is the only
                // remaining copy on the USB — leave it for manual recovery
                if fm.fileExists(atPath: copy.destination.path) {
                    try? fm.removeItem(at: tempURL)
                }
                throw error
            }
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
                index[fileURL.lastPathComponent.precomposedStringWithCanonicalMapping, default: []].append(fileURL)
            }
        }
        return index
    }
}
