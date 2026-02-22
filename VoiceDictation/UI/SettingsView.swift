import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    @AppStorage("transcriptionMode") private var transcriptionMode: String = "local"
    @AppStorage("openaiApiKey") private var openaiApiKey: String = ""
    @AppStorage("selectedModelName") private var selectedModelName: String = "tiny.en"
    @AppStorage("language") private var language: String = "en"
    @AppStorage("formattingMode") private var formattingMode: String = "rules"
    @AppStorage("writingTone") private var writingTone: String = "formal"
    @AppStorage("soundFeedbackEnabled") private var soundFeedbackEnabled: Bool = true
    @AppStorage("autoPasteEnabled") private var autoPasteEnabled: Bool = true
    @AppStorage("customVocabulary") private var customVocabulary: String = ""

    @ObservedObject private var launchAtLogin = LaunchAtLogin.shared
    @ObservedObject private var appToneManager = AppToneManager.shared
    @State private var showingAppPicker = false

    private let modelOptions = ["tiny.en", "base.en", "small.en", "medium.en"]
    private let languageOptions = [
        ("en", "English"),
        ("auto", "Auto-detect"),
        ("fr", "French"),
        ("de", "German"),
        ("es", "Spanish"),
        ("ja", "Japanese"),
        ("zh", "Chinese"),
    ]

    var body: some View {
        Form {
            // MARK: - General
            Section("General") {
                Toggle("Launch at Login", isOn: $launchAtLogin.isEnabled)

                Toggle("Sound feedback", isOn: $soundFeedbackEnabled)
                Text("Play a short tone when recording starts and stops.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Auto-paste into active app", isOn: $autoPasteEnabled)
                Text(autoPasteEnabled
                     ? "Text is automatically pasted into the frontmost app after dictation."
                     : "Text is copied to the clipboard. Paste it yourself with \u{2318}V.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: - OpenAI API Key
            Section("OpenAI API Key") {
                SecureField("sk-...", text: $openaiApiKey)
                    .textFieldStyle(.roundedBorder)

                if openaiApiKey.isEmpty {
                    Text("Add an OpenAI API key to enable fast cloud transcription and AI formatting. Get one at platform.openai.com")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("API key set")
                            .font(.caption)
                    }
                }
            }

            // MARK: - Transcription
            Section("Transcription") {
                Picker("Method", selection: $transcriptionMode) {
                    Text("Local whisper.cpp (free, slower)").tag("local")
                    Text("OpenAI Whisper API (fast, paid)").tag("api")
                }
                .pickerStyle(.radioGroup)

                if transcriptionMode == "api" {
                    if openaiApiKey.isEmpty {
                        Label("Enter your API key above to use cloud transcription", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text("~\u{00A3}0.005 per minute of audio. A typical 10-second clip costs less than \u{00A3}0.001.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if transcriptionMode == "local" {
                    Picker("Whisper model", selection: $selectedModelName) {
                        ForEach(modelOptions, id: \.self) { name in
                            Text(modelLabel(name)).tag(name)
                        }
                    }
                    .pickerStyle(.menu)

                    Button("Download selected model") {
                        WhisperModelManager.shared.downloadModel(named: selectedModelName)
                    }
                    .disabled(WhisperModelManager.shared.isModelDownloaded(named: selectedModelName))
                }
            }

            // MARK: - Formatting
            Section("Formatting") {
                Picker("Method", selection: $formattingMode) {
                    Text("Off (raw text)").tag("off")
                    Text("Rule-based (free, offline)").tag("rules")
                    Text("AI \u{2014} GPT-4o-mini (best quality)").tag("ai")
                }
                .pickerStyle(.radioGroup)

                if formattingMode == "ai" {
                    if openaiApiKey.isEmpty {
                        Label("Enter your API key above to use AI formatting", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text("Adds proper punctuation, capitalisation, bullet points, and paragraph structure. Costs fractions of a penny per use.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if formattingMode == "rules" {
                    Text("Say \"bullet point\", \"new line\", \"comma\", etc. to add formatting. Free and works offline.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if formattingMode != "off" {
                    Divider()

                    Picker("Tone", selection: $writingTone) {
                        Text("Formal \u{2014} Hey, are you free for lunch tomorrow?").tag("formal")
                        Text("Casual \u{2014} Hey are you free for lunch tomorrow?").tag("casual")
                        Text("Very casual \u{2014} hey are you free for lunch tomorrow?").tag("very_casual")
                    }
                    .pickerStyle(.radioGroup)

                    Text(toneDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: - Per-App Tone
            if formattingMode != "off" {
                Section("Per-App Tone") {
                    if appToneManager.overrides.isEmpty {
                        Text("No per-app overrides. The global tone above is used everywhere.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appToneManager.overrides) { override in
                            HStack {
                                if let icon = appIcon(for: override.bundleID) {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 20, height: 20)
                                }
                                Text(override.appName)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Picker("", selection: Binding(
                                    get: { override.tone.rawValue },
                                    set: { newValue in
                                        if let tone = TextFormatter.Tone(rawValue: newValue) {
                                            appToneManager.setTone(tone, forApp: override.bundleID, appName: override.appName)
                                        }
                                    }
                                )) {
                                    Text("Formal").tag("formal")
                                    Text("Casual").tag("casual")
                                    Text("Very casual").tag("very_casual")
                                }
                                .pickerStyle(.menu)
                                .frame(width: 120)

                                Button {
                                    appToneManager.removeTone(forApp: override.bundleID)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button("Add App\u{2026}") {
                        showingAppPicker = true
                    }
                    .popover(isPresented: $showingAppPicker) {
                        AppPickerView(appToneManager: appToneManager) {
                            showingAppPicker = false
                        }
                    }

                    Text("Override the tone for specific apps. The frontmost app is detected automatically when you dictate.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: - Custom Vocabulary
            Section("Custom Vocabulary") {
                TextEditor(text: $customVocabulary)
                    .font(.body.monospaced())
                    .frame(height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )

                Text("One entry per line. Use \u{201C}wrong \u{2192} right\u{201D} for replacements, or just a word for hints.\nExamples: \u{201C}shiv on \u{2192} Siobhan\u{201D}, \u{201C}Kubernetes\u{201D}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: - Language
            Section("Language") {
                Picker("Language", selection: $language) {
                    ForEach(languageOptions, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
                .pickerStyle(.menu)
            }

            // MARK: - Hotkey
            Section("Hotkey") {
                HotKeyRecorderView(onHotkeyChanged: {
                    // Tell the running HotKeyMonitor to pick up the new configuration.
                    if let delegate = NSApp.delegate as? AppDelegate {
                        delegate.hotKeyMonitor?.reloadConfiguration()
                    }
                })
            }

            // MARK: - Permissions
            Section("Permissions") {
                PermissionsStatusView()
            }

            // MARK: - About
            Section("About") {
                HStack {
                    Text("VoiceDictation")
                        .font(.headline)
                    Text("v\(appVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Hold a hotkey, speak, release \u{2014} your words appear as text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    Button {
                        NSWorkspace.shared.open(URL(string: "https://github.com/jackl123/voice-dictation")!)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                            Text("GitHub")
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)

                    Button {
                        NSWorkspace.shared.open(URL(string: "mailto:larner.j+voice@gmail.com?subject=VoiceDictation%20Feedback%20(v\(appVersion))")!)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "envelope")
                            Text("Send Feedback")
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 440, maxWidth: 440, minHeight: 400, maxHeight: .infinity)
        .padding()
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var toneDescription: String {
        switch writingTone {
        case "formal":
            return "Proper capitalisation with full punctuation. Best for emails and professional writing."
        case "casual":
            return "Normal capitalisation with lighter punctuation. Good for messages and everyday writing."
        case "very_casual":
            return "All lowercase with minimal punctuation. Perfect for texting and chat."
        default:
            return ""
        }
    }

    private func appIcon(for bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private func modelLabel(_ name: String) -> String {
        switch name {
        case "tiny.en":   return "Tiny (75 MB) \u{2014} fastest"
        case "base.en":   return "Base (142 MB) \u{2014} balanced"
        case "small.en":  return "Small (466 MB) \u{2014} accurate"
        case "medium.en": return "Medium (1.5 GB) \u{2014} most accurate"
        default:           return name
        }
    }
}

// MARK: - Permissions status mini-view

struct PermissionsStatusView: View {
    @ObservedObject private var checker = PermissionChecker.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            permissionRow("Microphone", granted: checker.microphoneGranted, action: {
                PermissionChecker.shared.requestMicrophone()
            })
            permissionRow("Input Monitoring", granted: checker.inputMonitoringGranted, action: {
                PermissionChecker.shared.openInputMonitoringSettings()
            })
            permissionRow("Accessibility", granted: checker.accessibilityGranted, action: {
                PermissionChecker.shared.openAccessibilitySettings()
            })
        }
    }

    @ViewBuilder
    private func permissionRow(_ name: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
            Text(name)
            Spacer()
            if !granted {
                Button("Grant") { action() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}

// MARK: - App picker popover

/// Shows a list of running applications to pick from when adding a per-app tone override.
struct AppPickerView: View {
    let appToneManager: AppToneManager
    let onDismiss: () -> Void
    @State private var searchText = ""

    private var availableApps: [(name: String, bundleID: String, icon: NSImage)] {
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }  // Only user-facing apps
            .compactMap { app -> (name: String, bundleID: String, icon: NSImage)? in
                guard let name = app.localizedName,
                      let bundleID = app.bundleIdentifier else { return nil }
                // Exclude apps that already have overrides.
                guard !appToneManager.overrides.contains(where: { $0.bundleID == bundleID }) else { return nil }
                return (name: name, bundleID: bundleID, icon: app.icon ?? NSImage())
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if searchText.isEmpty { return running }
        return running.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search apps\u{2026}", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)

            Divider()

            if availableApps.isEmpty {
                VStack(spacing: 4) {
                    Text("No apps found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                List(availableApps, id: \.bundleID) { app in
                    Button {
                        appToneManager.setTone(.formal, forApp: app.bundleID, appName: app.name)
                        onDismiss()
                    } label: {
                        HStack {
                            Image(nsImage: app.icon)
                                .resizable()
                                .frame(width: 20, height: 20)
                            Text(app.name)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 250, height: 300)
    }
}
