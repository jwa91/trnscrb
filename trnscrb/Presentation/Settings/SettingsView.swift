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
    /// Called when the user closes the popover.
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            settingsContent
        }
        .frame(
            width: PopoverDesign.popoverSize.width,
            height: PopoverDesign.popoverSize.height
        )
        .background(PopoverDesign.surfaceBackground)
        .task { await viewModel.load() }
    }

    /// Navigation header with back button and save button.
    private var header: some View {
        PopoverChromeBar {
            SettingsBackButton(action: onBack)
        } center: {
            if let error = viewModel.error {
                Text(error)
                    .font(PopoverDesign.secondaryTextFont)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        } trailing: {
            HStack(spacing: 6) {
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

                ChromeIconButton(
                    systemName: "xmark",
                    title: "Close",
                    action: onClose
                )
            }
        }
    }

    /// Scrollable settings content with card grouping.
    private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                s3Section
                mistralSection
                providerSection
                outputSection
                generalSection
            }
            .padding(PopoverDesign.contentPadding)
        }
    }

    /// S3 Storage configuration fields.
    private var s3Section: some View {
        SettingsSectionCard(title: "S3 Storage") {
            fieldGroup(
                "Endpoint URL",
                help: "You can paste either https://host or just host; the app will use HTTPS."
            ) {
                TextField("https://s3.example.com", text: $viewModel.settings.s3EndpointURL)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
            }

            fieldGroup("Access Key") {
                TextField("Access Key", text: $viewModel.settings.s3AccessKey)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
            }

            fieldGroup("Secret Key") {
                secretField(
                    "Secret Key",
                    text: $viewModel.s3SecretKey,
                    isVisible: $viewModel.isS3SecretKeyVisible
                )
            }

            fieldGroup("Bucket Name") {
                TextField("Bucket Name", text: $viewModel.settings.s3BucketName)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
            }

            fieldGroup("Region") {
                TextField("Region", text: $viewModel.settings.s3Region)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
            }

            fieldGroup("Path Prefix") {
                TextField("Path Prefix", text: $viewModel.settings.s3PathPrefix)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
            }

            HStack(spacing: 10) {
                testButton("Test", result: viewModel.s3TestResult) {
                    Task { await viewModel.testS3() }
                }
                testResultView(viewModel.s3TestResult)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
    }

    /// Mistral API key field.
    private var mistralSection: some View {
        SettingsSectionCard(title: "Mistral API") {
            fieldGroup("API Key") {
                secretField(
                    "API Key",
                    text: $viewModel.mistralAPIKey,
                    isVisible: $viewModel.isMistralAPIKeyVisible
                )
            }

            HStack(spacing: 10) {
                testButton("Test", result: viewModel.mistralTestResult) {
                    Task { await viewModel.testMistral() }
                }
                testResultView(viewModel.mistralTestResult)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
    }

    /// Per-media provider mode preferences.
    private var providerSection: some View {
        SettingsSectionCard(title: "Processing Providers") {
            fieldGroup("Audio") {
                providerModePicker(selection: $viewModel.settings.audioProviderMode)
            }

            fieldGroup("PDF") {
                providerModePicker(selection: $viewModel.settings.pdfProviderMode)
            }

            fieldGroup("Image") {
                providerModePicker(selection: $viewModel.settings.imageProviderMode)
            }

            if !viewModel.isLocalAppleModeAvailable {
                Text("Local Apple mode requires macOS 26 or newer.")
                    .font(PopoverDesign.secondaryTextFont)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Output folder and clipboard configuration.
    private var outputSection: some View {
        SettingsSectionCard(title: "Output") {
            fieldGroup("Save Folder") {
                HStack(spacing: 8) {
                    TextField("Folder path", text: $viewModel.settings.saveFolderPath)
                        .textFieldStyle(.roundedBorder)

                    Button("Browse…") {
                        browseForSaveFolder()
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
            }

            Text("Markdown files are always saved to this folder.")
                .font(PopoverDesign.secondaryTextFont)
                .foregroundStyle(.secondary)

            Toggle("Copy markdown to clipboard", isOn: $viewModel.settings.copyToClipboard)
        }
    }

    /// General settings: retention and launch at login.
    private var generalSection: some View {
        SettingsSectionCard(title: "General") {
            fieldGroup("File Retention") {
                HStack(spacing: 8) {
                    TextField(
                        "Hours",
                        value: $viewModel.settings.fileRetentionHours,
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 88)

                    Text("hours")
                        .font(PopoverDesign.secondaryTextFont)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)
                }
                .controlSize(.large)
            }

            Toggle("Launch at Login", isOn: $viewModel.settings.launchAtLogin)
        }
    }

    private func fieldGroup<Content: View>(
        _ title: String,
        help: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(PopoverDesign.settingsLabelFont)
                .foregroundStyle(.primary)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)

            if let help {
                Text(help)
                    .font(PopoverDesign.secondaryTextFont)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Test button helpers

    private func testButton(
        _ title: String,
        result: TestResult,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(result == .testing)
            .pointingHandCursor()
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
                .font(PopoverDesign.secondaryTextFont)
                .foregroundStyle(.green)
        case .failure(let message):
            Text(message)
                .font(PopoverDesign.secondaryTextFont)
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
            .controlSize(.large)

            Button {
                isVisible.wrappedValue.toggle()
            } label: {
                Image(systemName: isVisible.wrappedValue ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .pointingHandCursor()
            .help(isVisible.wrappedValue ? "Hide value" : "Show value")
        }
    }

    private func providerModePicker(selection: Binding<ProviderMode>) -> some View {
        Picker("", selection: selection) {
            Text("Mistral").tag(ProviderMode.mistral)
            Text("Local Apple (macOS 26+)")
                .tag(ProviderMode.localApple)
                .disabled(!viewModel.isLocalAppleModeAvailable)
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.large)
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
                .font(.system(size: 14, weight: .semibold))
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
