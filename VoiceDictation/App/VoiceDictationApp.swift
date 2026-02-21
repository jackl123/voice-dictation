import SwiftUI

@main
struct VoiceDictationApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No main window — this is a menu bar only app.
        // Settings window is managed manually by MenuBarController
        // because SwiftUI's Settings scene doesn't work reliably
        // in menu bar apps.
        Settings {
            EmptyView()
        }
    }
}
