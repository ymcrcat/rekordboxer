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
            switch selection {
            case .sync:
                SyncView()
            case .usb:
                USBSyncView()
            case .settings:
                SettingsView()
            case nil:
                Text("Select an item from the sidebar")
                    .foregroundStyle(.secondary)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            selection = .settings
        }
    }
}
