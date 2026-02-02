import SwiftUI
import UniformTypeIdentifiers
import RekordboxerCore

struct SettingsView: View {
    @State private var sourceFolderPath: String = ""
    @State private var xmlFilePath: String = ""
    @State private var statusMessage: String = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
            }
            .padding()
            Divider()

            Form {
                Section("Source Folder") {
                    HStack {
                        TextField("Path to music folder", text: $sourceFolderPath)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                        Button("Browse...") {
                            browseFolder()
                        }
                    }
                    Text("The root folder containing subfolders of audio files")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Rekordbox XML File") {
                    HStack {
                        TextField("Path to XML file", text: $xmlFilePath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse...") {
                            browseXML()
                        }
                    }
                    Text("The Rekordbox XML file to read from and write to")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            if let errorMessage = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(errorMessage)
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding(.horizontal)
            }

            HStack {
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .onAppear {
            loadSettings()
        }
    }

    private func loadSettings() {
        do {
            let settings = try AppSettings.load(from: AppSettings.defaultURL)
            sourceFolderPath = settings.sourceFolderPath
            xmlFilePath = settings.xmlFilePath
        } catch {
            // No existing settings, start fresh
        }
    }

    private func save() {
        errorMessage = nil
        var settings = AppSettings()
        settings.sourceFolderPath = sourceFolderPath
        settings.xmlFilePath = xmlFilePath

        do {
            try settings.save(to: AppSettings.defaultURL)
            statusMessage = "Settings saved."
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }

    private func browseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select your music source folder"

        if panel.runModal() == .OK, let url = panel.url {
            sourceFolderPath = url.path
        }
    }

    private func browseXML() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.xml]
        panel.nameFieldStringValue = "rekordbox.xml"
        panel.message = "Choose where to save the Rekordbox XML file"

        if panel.runModal() == .OK, let url = panel.url {
            xmlFilePath = url.path
        }
    }
}
