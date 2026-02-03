import SwiftUI
import RekordboxerCore

struct SyncView: View {
    @StateObject private var viewModel = SyncViewModel()

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

            if let diff = viewModel.diff {
                diffContent(diff)
            } else {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Press Refresh to compare your music folder with the Rekordbox XML")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()
            statusBar
        }
        .onAppear {
            viewModel.loadOnAppear()
        }
    }

    private var toolbar: some View {
        HStack {
            Text("Library Sync")
                .font(.headline)
            Spacer()
            Button {
                viewModel.scan()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isScanning)

            if viewModel.diff != nil {
                Button {
                    viewModel.syncToXML()
                } label: {
                    Label("Sync to XML", systemImage: "arrow.down.doc")
                }
            }
        }
        .padding()
    }

    private func diffContent(_ diff: SyncDiff) -> some View {
        List {
            if !viewModel.scannedFolders.isEmpty {
                Section {
                    ForEach(viewModel.scannedFolders, id: \.folderURL) { folder in
                        FolderRow(folder: folder, viewModel: viewModel)
                    }
                } header: {
                    Text("Folders")
                }
            }

            if !diff.removedTracks.isEmpty {
                Section {
                    ForEach(diff.removedTracks, id: \.trackID) { track in
                        HStack {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                            Toggle(isOn: Binding(
                                get: { viewModel.removalSelections.contains(track.trackID) },
                                set: { isOn in
                                    if isOn {
                                        viewModel.removalSelections.insert(track.trackID)
                                    } else {
                                        viewModel.removalSelections.remove(track.trackID)
                                    }
                                }
                            )) {
                                VStack(alignment: .leading) {
                                    Text(track.name)
                                    Text(track.artist)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Removed Tracks (\(diff.removedTracks.count))")
                }
            }

            Section {
                HStack {
                    Image(systemName: "music.note.list")
                        .foregroundStyle(.blue)
                    Text("\(viewModel.selectedNewTrackCount) new tracks in \(viewModel.selectedFolderCount) selected folders, \(diff.removedTracks.count) removed, \(diff.unchangedCount) unchanged")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Summary")
            }
        }
    }

    private var statusBar: some View {
        HStack {
            if viewModel.isScanning {
                ProgressView()
                    .controlSize(.small)
            }
            if viewModel.syncSuccess {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(viewModel.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Text(viewModel.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}

struct FolderRow: View {
    let folder: ScannedFolder
    @ObservedObject var viewModel: SyncViewModel

    var body: some View {
        if folder.children.isEmpty {
            leafRow
        } else {
            DisclosureGroup {
                ForEach(folder.children, id: \.folderURL) { child in
                    FolderRow(folder: child, viewModel: viewModel)
                }
            } label: {
                folderLabel
            }
        }
    }

    private var leafRow: some View {
        folderLabel
    }

    private var folderLabel: some View {
        HStack {
            Button {
                viewModel.toggleFolder(folder)
            } label: {
                checkboxImage
            }
            .buttonStyle(.plain)

            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)
            Text(folder.folderName)
            Spacer()
            Text("\(folder.allFiles.count)")
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary)
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private var checkboxImage: some View {
        switch viewModel.folderCheckState(folder) {
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
