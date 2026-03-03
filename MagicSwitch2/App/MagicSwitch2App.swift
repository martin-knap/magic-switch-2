import SwiftUI

@main
struct MagicSwitch2App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No visible main window — app lives in the menu bar.
        Settings {
            SettingsView(
                deviceStore: appDelegate.deviceStore,
                serviceBrowser: appDelegate.serviceBrowser,
                connectionManager: appDelegate.connectionManager
            )
            .frame(minWidth: 700, minHeight: 480)
        }
    }
}
