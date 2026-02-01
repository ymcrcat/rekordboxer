import Foundation

public struct TrackIDMap: Codable {
    private var pathToID: [String: Int] = [:]
    private var nextID: Int = 1

    public init() {}

    public mutating func getOrAssign(path: String) -> Int {
        if let existing = pathToID[path] {
            return existing
        }
        let id = nextID
        pathToID[path] = id
        nextID += 1
        return id
    }

    public mutating func assign(path: String, trackID: Int) {
        pathToID[path] = trackID
        if trackID >= nextID {
            nextID = trackID + 1
        }
    }

    public func trackID(for path: String) -> Int? {
        pathToID[path]
    }

    public mutating func remove(path: String) {
        pathToID.removeValue(forKey: path)
    }

    public static func load(from url: URL) throws -> TrackIDMap {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(TrackIDMap.self, from: data)
    }

    public func save(to url: URL) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: url)
    }
}
