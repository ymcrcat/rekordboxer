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
                    if viewModel.playlistSelections.isEmpty {
                        Text("No playlists found. Run Library Sync first.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.playlistSelections.keys.sorted(), id: \.self) { name in
                            Toggle(name, isOn: Binding(
                                get: { viewModel.playlistSelections[name] ?? false },
                                set: { viewModel.playlistSelections[name] = $0 }
                            ))
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
        HStack {
            if viewModel.isSyncing {
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
