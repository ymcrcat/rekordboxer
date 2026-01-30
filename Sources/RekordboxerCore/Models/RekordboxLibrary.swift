import Foundation

public struct RekordboxLibrary {
    public var productName: String = "rekordbox"
    public var productVersion: String = ""
    public var productCompany: String = "AlphaTheta"
    public var tracks: [Int: Track] = [:]
    public var rootNode: PlaylistNode = PlaylistNode(type: .folder, name: "ROOT", children: [], trackKeys: [])

    public init() {}
}

public struct Track {
    public var trackID: Int
    public var name: String = ""
    public var artist: String = ""
    public var composer: String = ""
    public var album: String = ""
    public var grouping: String = ""
    public var genre: String = ""
    public var kind: String = ""
    public var size: Int64 = 0
    public var totalTime: Int = 0
    public var discNumber: Int = 0
    public var trackNumber: Int = 0
    public var year: Int = 0
    public var averageBpm: Double = 0.0
    public var dateAdded: String = ""
    public var dateModified: String = ""
    public var bitRate: Int = 0
    public var sampleRate: Double = 0.0
    public var comments: String = ""
    public var playCount: Int = 0
    public var lastPlayed: String = ""
    public var rating: Int = 0
    public var location: String = ""
    public var remixer: String = ""
    public var tonality: String = ""
    public var label: String = ""
    public var mix: String = ""
    public var colour: String = ""

    public var tempos: [Tempo] = []
    public var positionMarks: [PositionMark] = []
    public var rawAttributes: [String: String] = [:]

    public init(trackID: Int) {
        self.trackID = trackID
    }

    public var filePath: String {
        Track.decodeLocation(location)
    }

    public static func ratingToStars(_ rating: Int) -> Int {
        guard rating > 0 else { return 0 }
        return rating / 51
    }

    public static func starsToRating(_ stars: Int) -> Int {
        return stars * 51
    }

    public static func encodeLocation(_ path: String) -> String {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return "file://localhost\(encoded)"
    }

    public static func decodeLocation(_ location: String) -> String {
        let withoutPrefix = location.replacingOccurrences(of: "file://localhost", with: "")
        return withoutPrefix.removingPercentEncoding ?? withoutPrefix
    }
}

public struct Tempo {
    public var inizio: Double
    public var bpm: Double
    public var metro: String
    public var battito: Int

    public init(inizio: Double, bpm: Double, metro: String, battito: Int) {
        self.inizio = inizio
        self.bpm = bpm
        self.metro = metro
        self.battito = battito
    }
}

public enum PositionMarkType: Int {
    case cue = 0
    case fadeIn = 1
    case fadeOut = 2
    case load = 3
    case loop = 4
}

public struct PositionMark {
    public var name: String
    public var type: PositionMarkType
    public var start: Double
    public var end: Double?
    public var num: Int
    public var red: Int?
    public var green: Int?
    public var blue: Int?

    public init(name: String, type: PositionMarkType, start: Double, end: Double?, num: Int, red: Int?, green: Int?, blue: Int?) {
        self.name = name
        self.type = type
        self.start = start
        self.end = end
        self.num = num
        self.red = red
        self.green = green
        self.blue = blue
    }

    public var isHotCue: Bool { num >= 0 }
    public var isMemoryCue: Bool { num == -1 }
    public var isLoop: Bool { type == .loop }
}

public enum PlaylistNodeType: Int {
    case folder = 0
    case playlist = 1
}

public struct PlaylistNode {
    public var type: PlaylistNodeType
    public var name: String
    public var children: [PlaylistNode]
    public var trackKeys: [Int]

    public init(type: PlaylistNodeType, name: String, children: [PlaylistNode], trackKeys: [Int]) {
        self.type = type
        self.name = name
        self.children = children
        self.trackKeys = trackKeys
    }

    public var isFolder: Bool { type == .folder }
    public var isPlaylist: Bool { type == .playlist }
}
