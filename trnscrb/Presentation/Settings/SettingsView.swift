import AppKit
import SwiftUI

/// Settings panel displayed inside the popover.
///
/// Shows all configurable fields from SPEC.md organized into sections.
/// API keys use `SecureField` and are stored in the Keychain, not the config file.
struct SettingsView: View {
    /// View model providing settings data and persistence.
    @ObservedObject var viewModel: SettingsViewModel
    /// Called when the user taps the back button.
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            settingsForm
        }
        .frame(width: 320, height: 480)
        .task { await viewModel.load() }
    }

    /// Navigation header with back button and save button.
    private var header: some View {
        PopoverChromeBar {
            SettingsBackButton(action: onBack)
        } center: {
            if let error = viewModel.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        } trailing: {
            Button("Save") {
                Task {
                    let didSave: Bool = await viewModel.save()
                    if didSave {
                        onBack()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .pointingHandCursor()
        }
    }

    /// Form containing all settings sections.
    private var settingsForm: some View {
        Form {
            s3Section
            mistralSection
            providerSection
            outputSection
            generalSection
        }
        .formStyle(.grouped)
    }

    /// S3 Storage configuration fields.
    private var s3Section: some View {
        Section("S3 Storage") {
            TextField("Endpoint URL", text: $viewModel.settings.s3EndpointURL)
                .textFieldStyle(.roundedBorder)
                .help("You can paste either https://host or just host; the app will use HTTPS.")
            TextField("Access Key", text: $viewModel.settings.s3AccessKey)
                .textFieldStyle(.roundedBorder)
            secretField(
                "Secret Key",
                text: $viewModel.s3SecretKey,
                isVisible: $viewModel.isS3SecretKeyVisible
            )
            TextField("Bucket Name", text: $viewModel.settings.s3BucketName)
                .textFieldStyle(.roundedBorder)
            TextField("Region", text: $viewModel.settings.s3Region)
                .textFieldStyle(.roundedBorder)
            TextField("Path Prefix", text: $viewModel.settings.s3PathPrefix)
                .textFieldStyle(.roundedBorder)
            HStack {
                testButton("Test", result: viewModel.s3TestResult) {
                    Task { await viewModel.testS3() }
                }
                testResultView(viewModel.s3TestResult)
            }
        }
    }

    /// Mistral API key field.
    private var mistralSection: some View {
        Section("Mistral API") {
            secretField(
                "API Key",
                text: $viewModel.mistralAPIKey,
                isVisible: $viewModel.isMistralAPIKeyVisible
            )
            HStack {
                testButton("Test", result: viewModel.mistralTestResult) {
                    Task { await viewModel.testMistral() }
                }
                testResultView(viewModel.mistralTestResult)
            }
        }
    }

    /// Per-media provider mode preferences.
    private var providerSection: some View {
        Section("Processing Providers") {
            providerModePicker("Audio", selection: $viewModel.settings.audioProviderMode)
            providerModePicker("PDF", selection: $viewModel.settings.pdfProviderMode)
            providerModePicker("Image", selection: $viewModel.settings.imageProviderMode)
            if !viewModel.isLocalAppleModeAvailable {
                Text("Local Apple mode requires macOS 26 or newer.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Output folder and clipboard configuration.
    private var outputSection: some View {
        Section("Output") {
            HStack(spacing: 8) {
                TextField("Save Folder", text: $viewModel.settings.saveFolderPath)
                    .textFieldStyle(.roundedBorder)
                Button("Browse…") {
                    browseForSaveFolder()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .pointingHandCursor()
            }
            Text("Markdown files are always saved to this folder.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if !viewModel.resolvedSaveFolderPath.isEmpty {
                Text(viewModel.resolvedSaveFolderPath)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Toggle("Copy markdown to clipboard", isOn: $viewModel.settings.copyToClipboard)
        }
    }

    /// General settings: retention and launch at login.
    private var generalSection: some View {
        Section("General") {
            HStack {
                Text("File Retention")
                Spacer()
                TextField(
                    "Hours",
                    value: $viewModel.settings.fileRetentionHours,
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                Text("hours")
                    .foregroundStyle(.secondary)
            }
            Toggle("Launch at Login", isOn: $viewModel.settings.launchAtLogin)
        }
    }

    // MARK: - Test button helpers

    private func testButton(
        _ title: String,
        result: TestResult,
        action: @escaping () -> Void
    ) -> some View {
        InlineTextActionButton(
            title: title,
            isEnabled: result != .testing,
            action: action
        )
    }

    @ViewBuilder
    private func testResultView(_ result: TestResult) -> some View {
        switch result {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView()
                .controlSize(.small)
        case .success:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        case .failure(let message):
            Text(message)
                .font(.caption2)
                .foregroundStyle(.red)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func secretField(
        _ title: String,
        text: Binding<String>,
        isVisible: Binding<Bool>
    ) -> some View {
        HStack(spacing: 8) {
            Group {
                if isVisible.wrappedValue {
                    TextField(title, text: text)
                } else {
                    SecureField(title, text: text)
                }
            }
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.middle)

            Button {
                isVisible.wrappedValue.toggle()
            } label: {
                Image(systemName: isVisible.wrappedValue ? "eye.slash" : "eye")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .pointingHandCursor()
            .help(isVisible.wrappedValue ? "Hide value" : "Show value")
        }
    }

    private func providerModePicker(
        _ title: String,
        selection: Binding<ProviderMode>
    ) -> some View {
        Picker(title, selection: selection) {
            Text("Mistral").tag(ProviderMode.mistral)
            Text("Local Apple (macOS 26+)")
                .tag(ProviderMode.localApple)
                .disabled(!viewModel.isLocalAppleModeAvailable)
        }
    }

    private func browseForSaveFolder() {
        NSApp.activate(ignoringOtherApps: true)
        let panel: NSOpenPanel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(
            fileURLWithPath: (viewModel.settings.saveFolderPath as NSString).expandingTildeInPath
        ).deletingLastPathComponent()

        if panel.runModal() == .OK, let selectedURL: URL = panel.url {
            viewModel.settings.saveFolderPath = selectedURL.standardizedFileURL.path()
        }
    }
}

private struct SettingsBackButton: View {
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            Label("Settings", systemImage: "chevron.left")
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { isHovered = $0 }
    }
}

private struct InlineTextActionButton: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .foregroundStyle(
                    isHovered && isEnabled ? Color.accentColor : Color.secondary
                )
                .underline(isHovered && isEnabled)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .pointingHandCursor()
        .onHover { isHovered = $0 }
    }
}
