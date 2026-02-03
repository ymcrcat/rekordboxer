import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case sync = "Library Sync"
    case usb = "USB Sync"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .sync: return "arrow.triangle.2.circlepath"
        case .usb: return "externaldrive"
        case .settings: return "gearshape"
        }
    }

    var helpTitle: String {
        switch self {
        case .sync: return "Library Sync"
        case .usb: return "USB Sync"
        case .settings: return "Settings"
        }
    }

    var helpDescription: String {
        switch self {
        case .sync:
            return """
            Sync your local audio library with Rekordbox.

            This feature scans your music source folder and compares it against your Rekordbox XML library file. It identifies:

            • New tracks in your source folder that aren't in Rekordbox yet
            • Tracks that have been removed from your source folder but still exist in the XML

            Select the tracks you want to add, then click "Export to XML" to update your Rekordbox library file. Import the updated XML in Rekordbox to complete the sync.

            To enable XML in Rekordbox:
            1. Open Rekordbox Preferences (⌘,)
            2. Go to Advanced > Database
            3. Under "rekordbox xml", check "Share library data with other DJ apps using rekordbox xml"
            4. Click "Change..." to set the XML file location
            5. Use File > Library > Import Playlist to load the XML after syncing
            """
        case .usb:
            return """
            Copy playlists to a USB drive for use with CDJs.

            Browse your Rekordbox playlists and select which ones to sync to a connected USB drive. The files will be copied with their folder structure preserved.

            • Select a USB volume from the dropdown
            • Check the playlists you want to export
            • Click "Sync to USB" to copy the audio files

            This is useful for preparing USB drives for DJ performances without using Rekordbox's export feature.
            """
        case .settings:
            return """
            Configure your library paths.

            Set up the locations that Rekordboxer uses to manage your music:

            • Source Folder: The root folder containing your audio files. This is where Rekordboxer looks for new tracks to add to your library.

            • Rekordbox XML: The path to your Rekordbox library XML file. Rekordboxer reads playlist and track information from this file and writes updates back to it.

            Enable "Export library XML" in Rekordbox preferences to generate the XML file.
            """
        }
    }
}

struct HelpPaneView: View {
    let item: SidebarItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(item.helpTitle, systemImage: "questionmark.circle")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(item.helpDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding()
        .frame(width: 240)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct ContentView: View {
    @State private var selection: SidebarItem? = .sync

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            HStack(spacing: 0) {
                switch selection {
                case .sync:
                    SyncView()
                        .frame(maxWidth: .infinity)
                case .usb:
                    USBSyncView()
                        .frame(maxWidth: .infinity)
                case .settings:
                    SettingsView()
                        .frame(maxWidth: .infinity)
                case nil:
                    Text("Select an item from the sidebar")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                if let item = selection {
                    Divider()
                    HelpPaneView(item: item)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            selection = .settings
        }
    }
}
