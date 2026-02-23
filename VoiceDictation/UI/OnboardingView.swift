import SwiftUI

// MARK: - Onboarding Step

private enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case permissions = 1
    case apiKey = 2
    case ready = 3
}

// MARK: - Main Onboarding View

struct OnboardingView: View {
    var onComplete: () -> Void

    @State private var currentStep: OnboardingStep = .welcome
    @AppStorage("openaiApiKey") private var openaiApiKey: String = ""
    @AppStorage("transcriptionMode") private var transcriptionMode: String = "local"
    @ObservedObject private var permissions = PermissionChecker.shared

    private var allPermissionsGranted: Bool {
        permissions.microphoneGranted && permissions.accessibilityGranted && permissions.inputMonitoringGranted
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress dots
            ProgressDotsView(currentStep: currentStep)
                .padding(.top, 24)

            // Step content
            Group {
                switch currentStep {
                case .welcome:
                    WelcomeStepView()
                case .permissions:
                    PermissionsStepView(permissions: permissions)
                case .apiKey:
                    APIKeyStepView(apiKey: $openaiApiKey)
                case .ready:
                    ReadyStepView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(currentStep)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

            // Navigation buttons
            navigationButtons
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
        }
        .frame(width: 480, height: 400)
        .animation(.easeInOut(duration: 0.3), value: currentStep)
    }

    // MARK: - Navigation

    @ViewBuilder
    private var navigationButtons: some View {
        switch currentStep {
        case .welcome:
            Button("Get Started") {
                advanceStep()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

        case .permissions:
            VStack(spacing: 8) {
                Button("Continue") {
                    advanceStep()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!allPermissionsGranted)

                if !allPermissionsGranted {
                    Text("Grant all permissions above to continue")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        case .apiKey:
            HStack(spacing: 16) {
                Button("Skip for now") {
                    advanceStep()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button("Continue") {
                    if !openaiApiKey.isEmpty {
                        transcriptionMode = "api"
                    }
                    advanceStep()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

        case .ready:
            Button("Start Dictating") {
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private func advanceStep() {
        guard let next = OnboardingStep(rawValue: currentStep.rawValue + 1) else { return }
        withAnimation {
            currentStep = next
        }
    }
}

// MARK: - Progress Dots

private struct ProgressDotsView: View {
    let currentStep: OnboardingStep

    var body: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                Circle()
                    .fill(step.rawValue <= currentStep.rawValue
                          ? Color.accentColor
                          : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }
}

// MARK: - Step 1: Welcome

private struct WelcomeStepView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "mic.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("Welcome to VoiceDictation")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Turn your voice into text, anywhere on your Mac.\nJust hold a key, speak, and release.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            Spacer()
        }
    }
}

// MARK: - Step 2: Permissions

private struct PermissionsStepView: View {
    @ObservedObject var permissions: PermissionChecker

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("A few quick permissions")
                .font(.title2)
                .fontWeight(.semibold)

            Text("VoiceDictation needs these to work properly.\nThey stay on your Mac and are never shared.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            VStack(spacing: 12) {
                permissionRow(
                    icon: "mic.fill",
                    name: "Microphone",
                    description: "To hear your voice",
                    granted: permissions.microphoneGranted,
                    action: { PermissionChecker.shared.requestMicrophone() }
                )

                permissionRow(
                    icon: "keyboard",
                    name: "Accessibility",
                    description: "To type text into apps",
                    granted: permissions.accessibilityGranted,
                    action: { PermissionChecker.shared.openAccessibilitySettings() }
                )

                permissionRow(
                    icon: "hand.raised.fill",
                    name: "Input Monitoring",
                    description: "To detect your hotkey",
                    granted: permissions.inputMonitoringGranted,
                    action: { PermissionChecker.shared.openInputMonitoringSettings() }
                )
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    @ViewBuilder
    private func permissionRow(
        icon: String,
        name: String,
        description: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(granted ? .green : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            } else {
                Button("Grant Access") { action() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

// MARK: - Step 3: API Key

private struct APIKeyStepView: View {
    @Binding var apiKey: String

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "key.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text("Supercharge with OpenAI")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Adding an API key gives you faster, more accurate\ntranscription and smart formatting.\n\nThis is optional \u{2014} the app works without it.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            VStack(alignment: .leading, spacing: 6) {
                Text("API Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("sk-...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
            }

            if !apiKey.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Key entered")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Link("Get an API key at platform.openai.com",
                 destination: URL(string: "https://platform.openai.com/api-keys")!)
                .font(.caption)

            Spacer()
        }
    }
}

// MARK: - Step 4: Ready

private struct ReadyStepView: View {
    private let hotkey = HotKeyConfiguration.load().displayString

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text("You\u{2019}re all set!")
                .font(.largeTitle)
                .fontWeight(.bold)

            VStack(spacing: 12) {
                instructionRow(step: "1", text: "Click anywhere you want to type")
                instructionRow(step: "2", text: "Hold \(hotkey) and speak")
                instructionRow(step: "3", text: "Release \(hotkey) \u{2014} your words appear as text")
            }
            .frame(maxWidth: 320)

            Text("Look for the mic icon in your menu bar to adjust settings later.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            Spacer()
        }
    }

    @ViewBuilder
    private func instructionRow(step: String, text: String) -> some View {
        HStack(spacing: 12) {
            Text(step)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor))

            Text(text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
