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

    @ObservedObject private var launchAtLogin = LaunchAtLogin.shared

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
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 880)
        .padding()
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
