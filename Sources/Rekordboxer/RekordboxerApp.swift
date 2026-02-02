import SwiftUI

extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
}

@main
struct RekordboxerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 700, minHeight: 500)
        }
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
