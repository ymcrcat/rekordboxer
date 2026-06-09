import Foundation

public enum CheckState: Equatable {
    case checked, unchecked, mixed
}

public enum PlaylistSelector {
    public static func path(for name: String, prefix: String) -> String {
        prefix.isEmpty ? name : "\(prefix)/\(name)"
    }

    public static func checkState(for node: PlaylistNode, prefix: String, selected: Set<String>) -> CheckState {
        let nodePath = path(for: node.name, prefix: prefix)
        if node.isPlaylist {
            return selected.contains(nodePath) ? .checked : .unchecked
        }
        let paths = allPaths(node: node, prefix: prefix)
        if paths.isEmpty { return .unchecked }
        let selectedCount = paths.filter { selected.contains($0) }.count
        if selectedCount == 0 { return .unchecked }
        if selectedCount == paths.count { return .checked }
        return .mixed
    }

    public static func allPaths(node: PlaylistNode, prefix: String) -> Set<String> {
        let nodePath = path(for: node.name, prefix: prefix)
        if node.isPlaylist { return [nodePath] }
        var result = Set<String>()
        for child in node.children {
            result.formUnion(allPaths(node: child, prefix: nodePath))
        }
        return result
    }

    public static func collectTrackKeys(
        from node: PlaylistNode,
        prefix: String,
        selected: Set<String>,
        into keys: inout [Int]
    ) {
        let nodePath = path(for: node.name, prefix: prefix)
        if node.isPlaylist {
            if selected.contains(nodePath) {
                keys.append(contentsOf: node.trackKeys)
            }
        } else {
            for child in node.children {
                collectTrackKeys(from: child, prefix: nodePath, selected: selected, into: &keys)
            }
        }
    }
}
