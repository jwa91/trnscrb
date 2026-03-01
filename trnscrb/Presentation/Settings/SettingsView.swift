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
        HStack {
            Button(action: onBack) {
                Label("Settings", systemImage: "chevron.left")
                    .font(.headline)
            }
            .buttonStyle(.borderless)
            Spacer()
            if let error = viewModel.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
            Button("Save") {
                Task {
                    await viewModel.save()
                    onBack()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Form containing all settings sections.
    private var settingsForm: some View {
        Form {
            s3Section
            mistralSection
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
            TextField("Access Key", text: $viewModel.settings.s3AccessKey)
                .textFieldStyle(.roundedBorder)
            SecureField("Secret Key", text: $viewModel.s3SecretKey)
                .textFieldStyle(.roundedBorder)
            TextField("Bucket Name", text: $viewModel.settings.s3BucketName)
                .textFieldStyle(.roundedBorder)
            TextField("Region", text: $viewModel.settings.s3Region)
                .textFieldStyle(.roundedBorder)
            TextField("Path Prefix", text: $viewModel.settings.s3PathPrefix)
                .textFieldStyle(.roundedBorder)
        }
    }

    /// Mistral API key field.
    private var mistralSection: some View {
        Section("Mistral API") {
            SecureField("API Key", text: $viewModel.mistralAPIKey)
                .textFieldStyle(.roundedBorder)
        }
    }

    /// Output folder and clipboard configuration.
    private var outputSection: some View {
        Section("Output") {
            TextField("Save Folder", text: $viewModel.settings.saveFolderPath)
                .textFieldStyle(.roundedBorder)
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
}
