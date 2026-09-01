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

    /// Reconcile the map with a loaded library: every existing track keeps its
    /// XML trackID, and nextID moves past the highest ID so new tracks can
    /// never collide with (and silently overwrite) existing ones.
    public mutating func seed(from tracks: [Int: Track]) {
        for (id, track) in tracks {
            assign(path: track.filePath, trackID: id)
        }
        // Purge stale entries claiming an ID the library assigns to a different
        // path — getOrAssign would hand that ID out again and overwrite the
        // library's track
        for (path, id) in pathToID {
            if let track = tracks[id], track.filePath != path {
                pathToID.removeValue(forKey: path)
            }
        }
    }

    public static func load(from url: URL) throws -> TrackIDMap {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(TrackIDMap.self, from: data)
    }

    public func save(to url: URL) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }
}
