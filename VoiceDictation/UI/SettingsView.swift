import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    @AppStorage("selectedModelName") private var selectedModelName: String = "tiny.en"
    @AppStorage("language") private var language: String = "en"
    @AppStorage("useAIFormatting") private var useAIFormatting: Bool = false
    @AppStorage("openaiApiKey") private var openaiApiKey: String = ""

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
            Section("Model") {
                Picker("Whisper model", selection: $selectedModelName) {
                    ForEach(modelOptions, id: \.self) { name in
                        Text(modelLabel(name)).tag(name)
                    }
                }
                .pickerStyle(.menu)

                Text("Larger models are more accurate but slower. tiny.en is a great starting point.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Download selected model") {
                    WhisperModelManager.shared.downloadModel(named: selectedModelName)
                }
                .disabled(WhisperModelManager.shared.isModelDownloaded(named: selectedModelName))
            }

            Section("Language") {
                Picker("Language", selection: $language) {
                    ForEach(languageOptions, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Formatting") {
                Toggle("AI formatting (OpenAI)", isOn: $useAIFormatting)

                if useAIFormatting {
                    SecureField("OpenAI API Key", text: $openaiApiKey)
                        .textFieldStyle(.roundedBorder)

                    Text("Uses GPT-4o-mini to intelligently format your transcription with proper punctuation, bullet points, and structure. Costs roughly \u{00A3}0.01/month with typical use.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !openaiApiKey.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("API key set")
                                .font(.caption)
                        }
                    }
                }

                Text("Without AI: spoken commands like \"bullet point\", \"new line\", \"comma\" are converted to formatting automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Hotkey") {
                LabeledContent("Record", value: "\u{2325} Space (hold)")
                Text("Hold Option+Space to record, release to transcribe.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                PermissionsStatusView()
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 500)
        .padding()
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
