import SwiftUI

@main
struct VoiceDictationApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No main window — this is a menu bar only app.
        // Settings window is opened programmatically from the menu.
        Settings {
            LazySettingsView()
                .environmentObject(appDelegate.appState)
        }
    }
}

/// Defers SettingsView construction until the window actually appears on screen.
/// This prevents eager evaluation of PermissionChecker.shared and file I/O
/// during app launch.
struct LazySettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var appeared = false

    var body: some View {
        Group {
            if appeared {
                SettingsView()
            } else {
                ProgressView("Loading settings…")
                    .frame(width: 420, height: 400)
            }
        }
        .onAppear { appeared = true }
    }
}
