import Foundation

public struct USBManifestEntry: Codable {
    public var size: Int64
    public var modificationDate: Date

    public init(size: Int64, modificationDate: Date) {
        self.size = size
        self.modificationDate = modificationDate
    }
}

public struct USBManifest: Codable {
    public var entries: [String: USBManifestEntry] = [:]

    public init() {}

    public static func load(from url: URL) throws -> USBManifest {
        guard FileManager.default.fileExists(atPath: url.path) else { return USBManifest() }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(USBManifest.self, from: data)
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(self)
        try data.write(to: url)
    }
}

public struct USBSyncPlan {
    public struct FileCopy {
        public let source: URL
        public let destination: URL
        public let filename: String
    }

    public let filesToCopy: [FileCopy]
    public let usbRoot: URL
}

public enum USBSync {
    public static func plan(tracks: [Track], usbRoot: URL, manifest: USBManifest) throws -> USBSyncPlan {
        let fm = FileManager.default
        var copies: [USBSyncPlan.FileCopy] = []

        for track in tracks {
            let sourcePath = track.filePath
            let sourceURL = URL(fileURLWithPath: sourcePath)
            let filename = sourceURL.lastPathComponent
            let destURL = usbRoot.appendingPathComponent(filename)

            guard fm.fileExists(atPath: sourcePath) else { continue }

            let attrs = try fm.attributesOfItem(atPath: sourcePath)
            let sourceSize = (attrs[.size] as? Int64) ?? 0
            let sourceModDate = (attrs[.modificationDate] as? Date) ?? Date()

            if let entry = manifest.entries[filename] {
                if entry.size == sourceSize && abs(entry.modificationDate.timeIntervalSince(sourceModDate)) < 1.0 {
                    continue
                }
            }

            copies.append(USBSyncPlan.FileCopy(source: sourceURL, destination: destURL, filename: filename))
        }

        return USBSyncPlan(filesToCopy: copies, usbRoot: usbRoot)
    }

    public static func execute(plan: USBSyncPlan) throws -> USBManifest {
        let fm = FileManager.default
        var manifest = USBManifest()

        for copy in plan.filesToCopy {
            if fm.fileExists(atPath: copy.destination.path) {
                try fm.removeItem(at: copy.destination)
            }
            try fm.copyItem(at: copy.source, to: copy.destination)

            let attrs = try fm.attributesOfItem(atPath: copy.source.path)
            manifest.entries[copy.filename] = USBManifestEntry(
                size: (attrs[.size] as? Int64) ?? 0,
                modificationDate: (attrs[.modificationDate] as? Date) ?? Date()
            )
        }

        return manifest
    }
}
