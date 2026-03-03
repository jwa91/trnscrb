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
                    let didSave: Bool = await viewModel.save()
                    if didSave {
                        onBack()
                    }
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

    /// Output folder and clipboard configuration.
    private var outputSection: some View {
        Section("Output") {
            TextField("Save Folder", text: $viewModel.settings.saveFolderPath)
                .textFieldStyle(.roundedBorder)
            Toggle("Save markdown to folder", isOn: $viewModel.settings.saveToFolder)
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
        Button(title) { action() }
            .buttonStyle(.borderless)
            .font(.caption)
            .disabled(result == .testing)
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
            .buttonStyle(.borderless)
            .help(isVisible.wrappedValue ? "Hide value" : "Show value")
        }
    }
}
