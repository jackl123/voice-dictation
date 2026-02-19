import SwiftUI

@main
struct VoiceDictationApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No main window — this is a menu bar only app.
        // Settings window is opened programmatically from the menu.
        Settings {
            SettingsView()
                .environmentObject(appDelegate.appState)
        }
    }
}
