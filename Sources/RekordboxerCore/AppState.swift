import Foundation

public struct AppSettings: Codable {
    public var sourceFolderPath: String = ""
    public var xmlFilePath: String = ""

    public init() {}

    public static func load(from url: URL) throws -> AppSettings {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AppSettings.self, from: data)
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(self)
        try data.write(to: url)
    }

    public static var defaultURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Rekordboxer")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }

    public static var trackIDMapURL: URL {
        defaultURL.deletingLastPathComponent().appendingPathComponent("trackids.json")
    }
}
