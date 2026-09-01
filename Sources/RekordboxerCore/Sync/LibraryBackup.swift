import Foundation

/// Why a pending write to the rekordbox XML must not proceed.
public enum XMLStaleness: Equatable {
    /// The file changed on disk since it was loaded.
    case changedOnDisk
    /// No file existed at load time, but one exists now.
    case appearedOnDisk

    public var message: String {
        switch self {
        case .changedOnDisk:
            return "XML file changed on disk since the last scan. Refresh before syncing."
        case .appearedOnDisk:
            return "An XML file appeared on disk since the last scan. Refresh before syncing."
        }
    }
}

/// Backup, pruning, and staleness checks for the rekordbox XML file.
///
/// Lives in the core (not the view model) so it is reachable from tests: this
/// is the safety net that makes an overwrite recoverable.
public enum LibraryBackup {
    /// Timestamp used in backup filenames. POSIX locale so a non-Gregorian
    /// system calendar can't produce unsortable names.
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    /// Modification time of a file, or nil if it doesn't exist / can't be read.
    public static func modificationDate(of path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    /// Single source of truth for the staleness decision, used both before the
    /// write is queued and again immediately before bytes hit the disk.
    /// `nil` means it is safe to write.
    public static func staleness(loaded: Date?, current: Date?) -> XMLStaleness? {
        guard let loaded else {
            return current == nil ? nil : .appearedOnDisk
        }
        guard let current else { return nil }
        return current == loaded ? nil : .changedOnDisk
    }

    /// Copy the existing XML aside as `<name>.<timestamp>.bak`, then prune.
    /// No-op when the file doesn't exist yet.
    @discardableResult
    public static func backup(xmlPath: String, keep: Int = 5, now: Date = Date()) throws -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: xmlPath) else { return nil }

        var destination = URL(fileURLWithPath: "\(xmlPath).\(formatter.string(from: now)).bak")
        // Same-second backups would collide; uniquify rather than fail the sync
        var suffix = 2
        while fm.fileExists(atPath: destination.path) {
            destination = URL(fileURLWithPath: "\(xmlPath).\(formatter.string(from: now))-\(suffix).bak")
            suffix += 1
        }

        try fm.copyItem(at: URL(fileURLWithPath: xmlPath), to: destination)
        prune(xmlPath: xmlPath, keep: keep)
        return destination
    }

    /// Keep only the newest `keep` backups this app created. Matches only our
    /// own timestamp pattern so a user's hand-made `.bak` files survive.
    public static func prune(xmlPath: String, keep: Int = 5) {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: xmlPath)
        let dir = url.deletingLastPathComponent()
        let prefix = url.lastPathComponent + "."
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        let backups = names.filter {
            $0.hasPrefix(prefix)
                && $0.range(of: #"\.\d{8}-\d{6}(-\d+)?\.bak$"#, options: .regularExpression) != nil
        }.sorted()
        for name in backups.dropLast(keep) {
            try? fm.removeItem(at: dir.appendingPathComponent(name))
        }
    }
}
