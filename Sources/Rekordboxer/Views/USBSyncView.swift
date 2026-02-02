import SwiftUI
import RekordboxerCore

struct USBSyncView: View {
    @StateObject private var viewModel = USBSyncViewModel()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if let errorMessage = viewModel.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(errorMessage)
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding()
            }

            Form {
                Section("Volume") {
                    HStack {
                        Picker("USB Volume", selection: $viewModel.selectedVolume) {
                            Text("None").tag(nil as URL?)
                            ForEach(viewModel.mountedVolumes, id: \.self) { volume in
                                Text(volume.lastPathComponent).tag(volume as URL?)
                            }
                        }
                        Button("Refresh") {
                            viewModel.refreshVolumes()
                        }
                    }
                }

                Section("Playlists") {
                    if viewModel.playlistNodes.isEmpty {
                        Text("No playlists found. Run Library Sync first.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.playlistNodes, id: \.name) { node in
                            PlaylistRow(node: node, prefix: "", viewModel: viewModel)
                        }
                    }
                }

                if let plan = viewModel.plan {
                    Section("Files with different sizes (\(plan.filesToCopy.count))") {
                        ForEach(plan.filesToCopy, id: \.filename) { file in
                            Toggle(isOn: Binding(
                                get: { viewModel.copySelections.contains(file.filename) },
                                set: { selected in
                                    if selected {
                                        viewModel.copySelections.insert(file.filename)
                                    } else {
                                        viewModel.copySelections.remove(file.filename)
                                    }
                                }
                            )) {
                                HStack {
                                    Image(systemName: "doc.fill")
                                        .foregroundStyle(.blue)
                                    Text(file.filename)
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            statusBar
        }
        .onAppear {
            viewModel.loadOnAppear()
        }
    }

    private var toolbar: some View {
        HStack {
            Text("USB Sync")
                .font(.headline)
            Spacer()

            Button {
                viewModel.planSync()
            } label: {
                Label("Plan", systemImage: "list.bullet.clipboard")
            }

            if viewModel.plan != nil {
                Button {
                    viewModel.executeSync()
                } label: {
                    Label("Copy \(viewModel.copySelections.count) to USB", systemImage: "externaldrive.fill.badge.plus")
                }
                .disabled(viewModel.isSyncing || viewModel.copySelections.isEmpty)
            }
        }
        .padding()
    }

    private var statusBar: some View {
        VStack(spacing: 4) {
            if viewModel.isSyncing {
                ProgressView(value: viewModel.syncProgress)
                    .progressViewStyle(.linear)
            }
            HStack {
                Text(viewModel.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}

struct PlaylistRow: View {
    let node: PlaylistNode
    let prefix: String
    @ObservedObject var viewModel: USBSyncViewModel

    var body: some View {
        if node.isPlaylist {
            leafRow
        } else {
            DisclosureGroup {
                let childPrefix = prefix.isEmpty ? node.name : "\(prefix)/\(node.name)"
                ForEach(node.children, id: \.name) { child in
                    PlaylistRow(node: child, prefix: childPrefix, viewModel: viewModel)
                        .padding(.leading, 20)
                }
            } label: {
                nodeLabel
            }
        }
    }

    private var leafRow: some View {
        nodeLabel
    }

    private var nodeLabel: some View {
        HStack {
            Button {
                viewModel.toggleNode(node, prefix: prefix)
            } label: {
                checkboxImage
            }
            .buttonStyle(.plain)

            Image(systemName: node.isPlaylist ? "music.note.list" : "folder.fill")
                .foregroundStyle(.secondary)
            Text(node.name)
            Spacer()
            if !node.isPlaylist {
                let count = viewModel.allPlaylistPaths(node: node, prefix: prefix).count
                Text("\(count)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }
        }
    }

    @ViewBuilder
    private var checkboxImage: some View {
        switch viewModel.checkState(for: node, prefix: prefix) {
        case .checked:
            Image(systemName: "checkmark.square.fill")
                .foregroundStyle(.blue)
        case .unchecked:
            Image(systemName: "square")
                .foregroundStyle(.secondary)
        case .mixed:
            Image(systemName: "minus.square.fill")
                .foregroundStyle(.blue)
        }
    }
}
