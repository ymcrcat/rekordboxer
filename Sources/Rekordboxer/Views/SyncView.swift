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
                diffList(diff)
            } else {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Press Scan to compare your music folder with the Rekordbox XML")
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
                Label("Scan", systemImage: "magnifyingglass")
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

    private func diffList(_ diff: SyncDiff) -> some View {
        List {
            if !diff.newTracks.isEmpty {
                Section {
                    ForEach(diff.newTracks, id: \.url) { file in
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.green)
                            Text(file.url.lastPathComponent)
                        }
                    }
                } header: {
                    Text("New Tracks (\(diff.newTracks.count))")
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
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                    Text("\(diff.unchangedCount) unchanged tracks")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Unchanged")
            }
        }
    }

    private var statusBar: some View {
        HStack {
            if viewModel.isScanning {
                ProgressView()
                    .controlSize(.small)
            }
            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}
