import SwiftUI

extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
}

@main
struct RekordboxerApp: App {
    var body: some Scene {
        Window("Rekordboxer", id: "main") {
            ContentView()
                .frame(minWidth: 700, minHeight: 500)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appSettings) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
