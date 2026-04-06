import AppKit
import Speech
import SwiftUI

enum SettingsWindowDesign {
    static let defaultSize: CGSize = CGSize(width: 900, height: 640)
    static let minSize: CGSize = CGSize(width: 780, height: 580)
}

private enum SettingsPane: String, CaseIterable, Hashable, Identifiable {
    case general
    case processing
    case connections
    case pipeline
    case output
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .processing:
            return "Processing"
        case .connections:
            return "Connections"
        case .pipeline:
            return "Advanced Pipeline"
        case .output:
            return "Output"
        case .general:
            return "General"
        case .about:
            return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .processing:
            return "slider.horizontal.3"
        case .connections:
            return "network"
        case .pipeline:
            return "arrow.triangle.branch"
        case .output:
            return "square.and.arrow.down"
        case .general:
            return "gearshape"
        case .about:
            return "info.circle"
        }
    }

    var description: String {
        switch self {
        case .processing:
            return "Choose how each file type is processed: locally or in the cloud."
        case .connections:
            return "API keys for cloud processing and external services."
        case .pipeline:
            return "Mirror originals to S3-compatible storage for staging, archival, or automation."
        case .output:
            return "Control where markdown files are saved and how they are named."
        case .general:
            return "Set app-wide behavior, defaults, and everyday workflow options."
        case .about:
            return "Version details, configuration access, and support information."
        }
    }
}

private enum SettingsField: Hashable {
    case saveFolderPath
    case mistralAPIKey
    case s3SecretKey
}

/// Settings content displayed inside the dedicated settings window.
struct SettingsView: View {
    /// View model providing settings data and persistence.
    @ObservedObject var viewModel: SettingsViewModel
    @State private var selectedPane: SettingsPane = .general
    @State private var lastObservedSettings: AppSettings?
    @State private var lastSavedCredentials: [SecretKey: String] = [:]
    @State private var saveFolderPathDraft: String = AppSettings().saveFolderPath
    @FocusState private var focusedField: SettingsField?

    var body: some View {
        TabView(selection: $selectedPane) {
            Tab("General", systemImage: SettingsPane.general.systemImage, value: .general) {
                pageContent(for: .general)
            }

            Tab("Processing", systemImage: SettingsPane.processing.systemImage, value: .processing) {
                pageContent(for: .processing)
            }

            Tab("Connections", systemImage: SettingsPane.connections.systemImage, value: .connections) {
                pageContent(for: .connections)
            }

            Tab(
                "Advanced Pipeline",
                systemImage: SettingsPane.pipeline.systemImage,
                value: .pipeline
            ) {
                pageContent(for: .pipeline)
            }

            Tab("Output", systemImage: SettingsPane.output.systemImage, value: .output) {
                pageContent(for: .output)
            }

            Tab("About", systemImage: SettingsPane.about.systemImage, value: .about) {
                pageContent(for: .about)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .frame(
            minWidth: SettingsWindowDesign.minSize.width,
            minHeight: SettingsWindowDesign.minSize.height
        )
        .task {
            await viewModel.load()
            saveFolderPathDraft = viewModel.settings.saveFolderPath
            lastSavedCredentials = [
                .mistralAPIKey: viewModel.mistralAPIKey,
                .s3SecretKey: viewModel.s3SecretKey
            ]
            if viewModel.error == nil {
                lastObservedSettings = viewModel.settings
            }
        }
        .onChange(of: viewModel.settings) { _, newValue in
            guard shouldAutosave(for: newValue) else { return }
            viewModel.debouncedSaveSettings()
        }
        .onChange(of: viewModel.settings.saveFolderPath) { _, newValue in
            guard focusedField != .saveFolderPath else { return }
            if saveFolderPathDraft != newValue {
                saveFolderPathDraft = newValue
            }
        }
        .onChange(of: focusedField) { oldValue, newValue in
            guard oldValue != newValue else { return }
            if oldValue == .saveFolderPath, newValue != .saveFolderPath {
                commitSaveFolderPathDraft()
            }
            if oldValue == .mistralAPIKey, newValue != .mistralAPIKey {
                commitCredentialIfNeeded(.mistralAPIKey)
            }
            if oldValue == .s3SecretKey, newValue != .s3SecretKey {
                commitCredentialIfNeeded(.s3SecretKey)
            }
        }
        .onDisappear {
            guard lastObservedSettings != nil else { return }
            commitSaveFolderPathDraft()
            commitCredentialIfNeeded(.mistralAPIKey)
            commitCredentialIfNeeded(.s3SecretKey)
            Task { await viewModel.saveSettings() }
        }
        .alert("Settings Error", isPresented: .init(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK") { viewModel.error = nil }
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    @ViewBuilder
    private func pageContent(for pane: SettingsPane) -> some View {
        switch pane {
        case .processing:
            processingPage
        case .connections:
            connectionsPage
        case .pipeline:
            pipelinePage
        case .output:
            outputPage
        case .general:
            generalPage
        case .about:
            aboutPage
        }
    }

    private func pageHeader(for pane: SettingsPane) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pane.title)
                .font(.title2).fontWeight(.bold)
            Text(pane.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .textCase(nil)
    }

    private var pipelinePage: some View {
        Form {
            Section {
                EmptyView()
            } header: {
                pageHeader(for: .pipeline)
            }

            Section {
                Toggle(
                    "Mirror originals to S3",
                    isOn: $viewModel.settings.bucketMirroringEnabled
                )
                .toggleStyle(.switch)
            } header: {
                Text("Bucket Mirroring")
            } footer: {
                Text("When enabled, original files are also uploaded to S3-compatible storage you configure. The S3 fields below only take effect when this is on.")
            }

            Section("S3 Connection") {
                LabeledContent("Endpoint URL") {
                    TextField(
                        "Endpoint URL",
                        text: $viewModel.settings.s3EndpointURL,
                        prompt: Text("https://s3.example.com")
                    )
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                }

                LabeledContent("Access Key") {
                    TextField("Access Key", text: $viewModel.settings.s3AccessKey)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                }

                LabeledContent("Secret Key") {
                    secretField(
                        "Secret Key",
                        text: $viewModel.s3SecretKey,
                        isVisible: $viewModel.isS3SecretKeyVisible,
                        secretKey: .s3SecretKey
                    )
                }

                LabeledContent("Bucket Name") {
                    TextField("Bucket Name", text: $viewModel.settings.s3BucketName)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                }

                LabeledContent("Region") {
                    TextField("Region", text: $viewModel.settings.s3Region)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                }

                LabeledContent("Path Prefix") {
                    TextField("Path Prefix", text: $viewModel.settings.s3PathPrefix)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                }

                LabeledContent("Retention") {
                    HStack(spacing: 8) {
                        TextField(
                            "Hours",
                            value: $viewModel.settings.fileRetentionHours,
                            format: .number
                        )
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 96)

                        Text("hours")
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    Spacer()
                    testResultView(viewModel.s3TestResult)
                    testButton("Test Connection", result: viewModel.s3TestResult) {
                        Task { await viewModel.testS3() }
                    }
                }
            }
            .disabled(!viewModel.settings.requiresS3Credentials)
        }
        .formStyle(.grouped)
    }

    private var connectionsPage: some View {
        Form {
            Section {
                EmptyView()
            } header: {
                pageHeader(for: .connections)
            }

            Section {
                LabeledContent("API Key") {
                    secretField(
                        "API Key",
                        text: $viewModel.mistralAPIKey,
                        isVisible: $viewModel.isMistralAPIKeyVisible,
                        secretKey: .mistralAPIKey
                    )
                }

                HStack(spacing: 10) {
                    Spacer()
                    testResultView(viewModel.mistralTestResult)
                    testButton("Test Connection", result: viewModel.mistralTestResult) {
                        Task { await viewModel.testMistral() }
                    }
                }
            } header: {
                Text("Mistral API")
            } footer: {
                Text("Cloud mode sends selected files to Mistral using your API key. Local mode processes on this Mac.")
            }
        }
        .formStyle(.grouped)
    }

    private var processingPage: some View {
        Form {
            Section {
                EmptyView()
            } header: {
                pageHeader(for: .processing)
            }

            Section("Default Providers") {
                Picker("Audio", selection: $viewModel.settings.audioProviderMode) {
                    Text("Cloud").tag(ProviderMode.mistral)
                    Text("Local").tag(ProviderMode.localApple)
                }

                Picker("PDF", selection: $viewModel.settings.pdfProviderMode) {
                    Text("Cloud").tag(ProviderMode.mistral)
                    Text("Local").tag(ProviderMode.localApple)
                }

                Picker("Image", selection: $viewModel.settings.imageProviderMode) {
                    Text("Cloud").tag(ProviderMode.mistral)
                    Text("Local").tag(ProviderMode.localApple)
                }
            }

            Section {
                Picker("Language", selection: $viewModel.settings.appleAudioLocaleIdentifier) {
                    ForEach(appleAudioLocaleOptions) { option in
                        Text(option.label).tag(option.identifier)
                    }
                }
                .disabled(viewModel.settings.audioProviderMode != .localApple)
            } header: {
                Text("Apple On-Device Audio")
            } footer: {
                Text("Used only when Audio is set to Local. Match this to the recording language for better recognition quality.")
            }
        }
        .formStyle(.grouped)
    }

    private var outputPage: some View {
        Form {
            Section {
                EmptyView()
            } header: {
                pageHeader(for: .output)
            }

            Section {
                LabeledContent("Save Folder") {
                    HStack(spacing: 8) {
                        TextField("Folder path", text: $saveFolderPathDraft)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .saveFolderPath)
                            .onSubmit {
                                commitSaveFolderPathDraft()
                            }

                        Button("Browse…") {
                            browseForSaveFolder()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } header: {
                Text("Saving")
            } footer: {
                Text("Markdown files are always saved to this folder.")
            }

            Section {
                LabeledContent("Filename Prefix") {
                    TextField(
                        "Filename Prefix",
                        text: $viewModel.settings.outputFileNamePrefix,
                        prompt: Text("notes-")
                    )
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                }

                LabeledContent("Filename Template") {
                    TextField(
                        AppSettings.defaultFileNameTemplate,
                        text: $viewModel.settings.outputFileNameTemplate
                    )
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                }

                LabeledContent("Preview") {
                    Text(viewModel.outputFileNamePreview)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } header: {
                Text("File Naming")
            } footer: {
                Text("Available variables: {originalFilename}, {fileType}, {timestamp}, {date}, {time}, {prefix}. The .md extension is added automatically.")
            }
        }
        .formStyle(.grouped)
    }

    private var generalPage: some View {
        Form {
            Section {
                EmptyView()
            } header: {
                pageHeader(for: .general)
            }

            Section {
                Toggle("Copy markdown to clipboard", isOn: $viewModel.settings.copyToClipboard)
            } header: {
                Text("Behavior")
            } footer: {
                Text("Also places the generated markdown on the clipboard after each run.")
            }

            Section {
                Toggle("Launch at Login", isOn: $viewModel.settings.launchAtLogin)
            } header: {
                Text("Startup")
            } footer: {
                Text("Starts the menu bar app automatically when you sign in to macOS.")
            }
        }
        .formStyle(.grouped)
    }

    private var aboutPage: some View {
        Form {
            Section {
                EmptyView()
            } header: {
                pageHeader(for: .about)
            }

            Section("Application") {
                LabeledContent("Version") {
                    Text(appVersionSummary)
                        .textSelection(.enabled)
                }

                LabeledContent("Bundle ID") {
                    Text(Bundle.main.bundleIdentifier ?? AppIdentity.bundleIdentifier)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Configuration") {
                LabeledContent("Config File") {
                    Text(configFileURL.path())
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                LabeledContent("Actions") {
                    HStack(spacing: 8) {
                        Button("Reveal Config File") {
                            revealConfigFile()
                        }
                        .buttonStyle(.bordered)

                        Button("Open Config Folder") {
                            openConfigFolder()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            Section("Privacy") {
                Text("Local mode processes files on this Mac. Cloud mode sends selected files to Mistral, and S3 mirroring uploads originals to storage you configure.")
                    .foregroundStyle(.secondary)

                Button("Open Privacy Policy") {
                    openPrivacyPolicy()
                }
                .buttonStyle(.bordered)
            }
        }
        .formStyle(.grouped)
    }

    private var appVersionSummary: String {
        AppVersionInfo.summary()
    }

    private var configFileURL: URL {
        TOMLConfigManager.defaultConfigFileURL
    }

    private func openPrivacyPolicy() {
        guard let url: URL = URL(string: AppIdentity.privacyPolicyURLString) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Test button helpers

    private func testButton(
        _ title: String,
        result: TestResult,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
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
                .font(.footnote)
                .foregroundStyle(.green)
        case .failure(let message):
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
                .lineLimit(2)
                .truncationMode(.tail)
        }
    }

    private func secretField(
        _ title: String,
        text: Binding<String>,
        isVisible: Binding<Bool>,
        secretKey: SecretKey
    ) -> some View {
        HStack(spacing: 8) {
            Group {
                if isVisible.wrappedValue {
                    TextField(title, text: text)
                } else {
                    SecureField(title, text: text)
                }
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.middle)
            .focused($focusedField, equals: field(for: secretKey))
            .onSubmit {
                commitCredentialIfNeeded(secretKey)
            }

            Button {
                isVisible.wrappedValue.toggle()
            } label: {
                Image(systemName: isVisible.wrappedValue ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .pointingHandCursor()
            .help(isVisible.wrappedValue ? "Hide value" : "Show value")

            if viewModel.credentialSaved[secretKey] == true {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
        }
    }

    private var appleAudioLocaleOptions: [AppleSpeechLocaleOption] {
        AppleSpeechLocaleOption.options(
            including: viewModel.settings.appleAudioLocaleIdentifier
        )
    }

    private func browseForSaveFolder() {
        NSApp.activate(ignoringOtherApps: true)
        let panel: NSOpenPanel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        let expandedPath: String = (viewModel.settings.saveFolderPath as NSString).expandingTildeInPath
        if !expandedPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: expandedPath).deletingLastPathComponent()
        }

        if panel.runModal() == .OK, let selectedURL: URL = panel.url {
            let standardizedURL: URL = selectedURL.standardizedFileURL
            saveFolderPathDraft = standardizedURL.path()
            viewModel.chooseSaveFolder(standardizedURL)
        }
    }

    private func commitSaveFolderPathDraft() {
        viewModel.updateSaveFolderPathDraft(saveFolderPathDraft)
    }

    private func commitCredentialIfNeeded(_ key: SecretKey) {
        let valueToSave: String = currentCredentialValue(for: key)
        let trimmedValue: String = valueToSave.trimmedCredentialValue
        guard lastSavedCredentials[key] != trimmedValue else { return }
        Task {
            guard let savedValue: String = await viewModel.saveCredential(valueToSave, for: key) else {
                return
            }
            lastSavedCredentials[key] = savedValue
        }
    }

    private func currentCredentialValue(for key: SecretKey) -> String {
        switch key {
        case .mistralAPIKey:
            return viewModel.mistralAPIKey
        case .s3SecretKey:
            return viewModel.s3SecretKey
        }
    }

    private func field(for key: SecretKey) -> SettingsField {
        switch key {
        case .mistralAPIKey:
            return .mistralAPIKey
        case .s3SecretKey:
            return .s3SecretKey
        }
    }

    private func shouldAutosave(for settings: AppSettings) -> Bool {
        guard let lastObservedSettings else {
            self.lastObservedSettings = settings
            return false
        }
        guard lastObservedSettings != settings else { return false }
        self.lastObservedSettings = settings
        return true
    }

    private func revealConfigFile() {
        let fileManager: FileManager = FileManager.default
        let fileURL: URL = configFileURL
        if fileManager.fileExists(atPath: fileURL.path()) {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        } else {
            openConfigFolder()
        }
    }

    private func openConfigFolder() {
        let folderURL: URL = configFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.open(folderURL)
    }
}

private struct AppleSpeechLocaleOption: Identifiable, Hashable {
    let identifier: String
    let label: String

    var id: String { identifier }

    static func options(including selectedIdentifier: String) -> [AppleSpeechLocaleOption] {
        let locale: Locale = .autoupdatingCurrent
        var identifiers: Set<String> = Set(
            SFSpeechRecognizer.supportedLocales().map(\.identifier)
        )
        if !selectedIdentifier.isEmpty {
            identifiers.insert(selectedIdentifier)
        }

        return identifiers
            .map { identifier in
                let localizedName: String = locale.localizedString(forIdentifier: identifier)
                    ?? identifier
                return AppleSpeechLocaleOption(
                    identifier: identifier,
                    label: "\(localizedName) (\(identifier))"
                )
            }
            .sorted { lhs, rhs in
                lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
            }
    }
}
