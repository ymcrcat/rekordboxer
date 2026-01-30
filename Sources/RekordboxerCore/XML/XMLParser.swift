import Foundation

public enum RekordboxXMLParser {
    public static func parse(data: Data) throws -> RekordboxLibrary {
        let doc = try XMLDocument(data: data)
        guard let root = doc.rootElement(), root.name == "DJ_PLAYLISTS" else {
            throw RekordboxXMLError.invalidFormat("Missing DJ_PLAYLISTS root element")
        }

        var library = RekordboxLibrary()

        if let product = root.elements(forName: "PRODUCT").first {
            library.productName = product.attribute(forName: "Name")?.stringValue ?? ""
            library.productVersion = product.attribute(forName: "Version")?.stringValue ?? ""
            library.productCompany = product.attribute(forName: "Company")?.stringValue ?? ""
        }

        if let collection = root.elements(forName: "COLLECTION").first {
            for trackElement in collection.elements(forName: "TRACK") {
                let track = parseTrack(trackElement)
                library.tracks[track.trackID] = track
            }
        }

        if let playlists = root.elements(forName: "PLAYLISTS").first,
           let rootNode = playlists.elements(forName: "NODE").first {
            library.rootNode = parsePlaylistNode(rootNode)
        }

        return library
    }

    private static func parseTrack(_ element: XMLElement) -> Track {
        let trackID = intAttr(element, "TrackID")
        var track = Track(trackID: trackID)

        if let attributes = element.attributes {
            for attr in attributes {
                if let name = attr.name, let value = attr.stringValue {
                    track.rawAttributes[name] = value
                }
            }
        }

        track.name = stringAttr(element, "Name")
        track.artist = stringAttr(element, "Artist")
        track.composer = stringAttr(element, "Composer")
        track.album = stringAttr(element, "Album")
        track.grouping = stringAttr(element, "Grouping")
        track.genre = stringAttr(element, "Genre")
        track.kind = stringAttr(element, "Kind")
        track.size = int64Attr(element, "Size")
        track.totalTime = intAttr(element, "TotalTime")
        track.discNumber = intAttr(element, "DiscNumber")
        track.trackNumber = intAttr(element, "TrackNumber")
        track.year = intAttr(element, "Year")
        track.averageBpm = doubleAttr(element, "AverageBpm")
        track.dateAdded = stringAttr(element, "DateAdded")
        track.dateModified = stringAttr(element, "DateModified")
        track.bitRate = intAttr(element, "BitRate")
        track.sampleRate = doubleAttr(element, "SampleRate")
        track.comments = stringAttr(element, "Comments")
        track.playCount = intAttr(element, "PlayCount")
        track.lastPlayed = stringAttr(element, "LastPlayed")
        track.rating = intAttr(element, "Rating")
        track.location = stringAttr(element, "Location")
        track.remixer = stringAttr(element, "Remixer")
        track.tonality = stringAttr(element, "Tonality")
        track.label = stringAttr(element, "Label")
        track.mix = stringAttr(element, "Mix")
        track.colour = stringAttr(element, "Colour")

        for tempoElement in element.elements(forName: "TEMPO") {
            let tempo = Tempo(
                inizio: doubleAttr(tempoElement, "Inizio"),
                bpm: doubleAttr(tempoElement, "Bpm"),
                metro: stringAttr(tempoElement, "Metro"),
                battito: intAttr(tempoElement, "Battito")
            )
            track.tempos.append(tempo)
        }

        for pmElement in element.elements(forName: "POSITION_MARK") {
            let typeRaw = intAttr(pmElement, "Type")
            let pm = PositionMark(
                name: stringAttr(pmElement, "Name"),
                type: PositionMarkType(rawValue: typeRaw) ?? .cue,
                start: doubleAttr(pmElement, "Start"),
                end: optionalDoubleAttr(pmElement, "End"),
                num: intAttr(pmElement, "Num"),
                red: optionalIntAttr(pmElement, "Red"),
                green: optionalIntAttr(pmElement, "Green"),
                blue: optionalIntAttr(pmElement, "Blue")
            )
            track.positionMarks.append(pm)
        }

        return track
    }

    private static func parsePlaylistNode(_ element: XMLElement) -> PlaylistNode {
        let typeRaw = intAttr(element, "Type")
        let nodeType = PlaylistNodeType(rawValue: typeRaw) ?? .folder
        let name = stringAttr(element, "Name")

        if nodeType == .folder {
            let children = element.elements(forName: "NODE").map { parsePlaylistNode($0) }
            return PlaylistNode(type: .folder, name: name, children: children, trackKeys: [])
        } else {
            let trackKeys = element.elements(forName: "TRACK").map { intAttr($0, "Key") }
            return PlaylistNode(type: .playlist, name: name, children: [], trackKeys: trackKeys)
        }
    }

    private static func stringAttr(_ element: XMLElement, _ name: String) -> String {
        element.attribute(forName: name)?.stringValue ?? ""
    }

    private static func intAttr(_ element: XMLElement, _ name: String) -> Int {
        Int(element.attribute(forName: name)?.stringValue ?? "0") ?? 0
    }

    private static func int64Attr(_ element: XMLElement, _ name: String) -> Int64 {
        Int64(element.attribute(forName: name)?.stringValue ?? "0") ?? 0
    }

    private static func doubleAttr(_ element: XMLElement, _ name: String) -> Double {
        Double(element.attribute(forName: name)?.stringValue ?? "0") ?? 0.0
    }

    private static func optionalIntAttr(_ element: XMLElement, _ name: String) -> Int? {
        guard let str = element.attribute(forName: name)?.stringValue else { return nil }
        return Int(str)
    }

    private static func optionalDoubleAttr(_ element: XMLElement, _ name: String) -> Double? {
        guard let str = element.attribute(forName: name)?.stringValue else { return nil }
        return Double(str)
    }
}

public enum RekordboxXMLError: Error {
    case invalidFormat(String)
}
