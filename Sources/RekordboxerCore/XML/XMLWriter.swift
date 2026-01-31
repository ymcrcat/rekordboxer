import Foundation

public enum RekordboxXMLWriter {
    public static func write(library: RekordboxLibrary) throws -> Data {
        let root = XMLElement(name: "DJ_PLAYLISTS")
        root.addAttribute(XMLNode.attribute(withName: "Version", stringValue: "1.0.0") as! XMLNode)

        let doc = XMLDocument(rootElement: root)
        doc.version = "1.0"
        doc.characterEncoding = "UTF-8"

        let product = XMLElement(name: "PRODUCT")
        product.addAttribute(attr("Name", library.productName))
        product.addAttribute(attr("Version", library.productVersion))
        product.addAttribute(attr("Company", library.productCompany))
        root.addChild(product)

        let collection = XMLElement(name: "COLLECTION")
        collection.addAttribute(attr("Entries", String(library.tracks.count)))
        let sortedTracks = library.tracks.values.sorted { $0.trackID < $1.trackID }
        for track in sortedTracks {
            collection.addChild(writeTrack(track))
        }
        root.addChild(collection)

        let playlists = XMLElement(name: "PLAYLISTS")
        playlists.addChild(writePlaylistNode(library.rootNode))
        root.addChild(playlists)

        return doc.xmlData(options: [.nodePrettyPrint])
    }

    private static func writeTrack(_ track: Track) -> XMLElement {
        let element = XMLElement(name: "TRACK")

        let attrs: [(String, String)] = [
            ("TrackID", String(track.trackID)),
            ("Name", track.name),
            ("Artist", track.artist),
            ("Composer", track.composer),
            ("Album", track.album),
            ("Grouping", track.grouping),
            ("Genre", track.genre),
            ("Kind", track.kind),
            ("Size", String(track.size)),
            ("TotalTime", String(track.totalTime)),
            ("DiscNumber", String(track.discNumber)),
            ("TrackNumber", String(track.trackNumber)),
            ("Year", String(track.year)),
            ("AverageBpm", String(format: "%.2f", track.averageBpm)),
            ("DateAdded", track.dateAdded),
            ("DateModified", track.dateModified),
            ("BitRate", String(track.bitRate)),
            ("SampleRate", String(format: "%.0f", track.sampleRate)),
            ("Comments", track.comments),
            ("PlayCount", String(track.playCount)),
            ("LastPlayed", track.lastPlayed),
            ("Rating", String(track.rating)),
            ("Location", track.location),
            ("Remixer", track.remixer),
            ("Tonality", track.tonality),
            ("Label", track.label),
            ("Mix", track.mix),
            ("Colour", track.colour),
        ]

        for (name, value) in attrs {
            element.addAttribute(attr(name, value))
        }

        let knownNames = Set(attrs.map { $0.0 })
        for (name, value) in track.rawAttributes where !knownNames.contains(name) {
            element.addAttribute(attr(name, value))
        }

        for tempo in track.tempos {
            let tempoEl = XMLElement(name: "TEMPO")
            tempoEl.addAttribute(attr("Inizio", String(format: "%.3f", tempo.inizio)))
            tempoEl.addAttribute(attr("Bpm", String(format: "%.2f", tempo.bpm)))
            tempoEl.addAttribute(attr("Metro", tempo.metro))
            tempoEl.addAttribute(attr("Battito", String(tempo.battito)))
            element.addChild(tempoEl)
        }

        for pm in track.positionMarks {
            let pmEl = XMLElement(name: "POSITION_MARK")
            pmEl.addAttribute(attr("Name", pm.name))
            pmEl.addAttribute(attr("Type", String(pm.type.rawValue)))
            pmEl.addAttribute(attr("Start", String(format: "%.3f", pm.start)))
            if let end = pm.end {
                pmEl.addAttribute(attr("End", String(format: "%.3f", end)))
            }
            pmEl.addAttribute(attr("Num", String(pm.num)))
            if let r = pm.red { pmEl.addAttribute(attr("Red", String(r))) }
            if let g = pm.green { pmEl.addAttribute(attr("Green", String(g))) }
            if let b = pm.blue { pmEl.addAttribute(attr("Blue", String(b))) }
            element.addChild(pmEl)
        }

        return element
    }

    private static func writePlaylistNode(_ node: PlaylistNode) -> XMLElement {
        let element = XMLElement(name: "NODE")

        if node.isFolder {
            element.addAttribute(attr("Type", "0"))
            element.addAttribute(attr("Name", node.name))
            element.addAttribute(attr("Count", String(node.children.count)))
            for child in node.children {
                element.addChild(writePlaylistNode(child))
            }
        } else {
            element.addAttribute(attr("Name", node.name))
            element.addAttribute(attr("Type", "1"))
            element.addAttribute(attr("KeyType", "0"))
            element.addAttribute(attr("Entries", String(node.trackKeys.count)))
            for key in node.trackKeys {
                let trackEl = XMLElement(name: "TRACK")
                trackEl.addAttribute(attr("Key", String(key)))
                element.addChild(trackEl)
            }
        }

        return element
    }

    private static func attr(_ name: String, _ value: String) -> XMLNode {
        XMLNode.attribute(withName: name, stringValue: value) as! XMLNode
    }
}
