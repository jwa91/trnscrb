import AppKit
import Speech
import SwiftUI

enum SettingsWindowDesign {
    static let defaultSize: CGSize = CGSize(width: 900, height: 640)
    static let minSize: CGSize = CGSize(width: 780, height: 580)
    static let detailMaxWidth: CGFloat = 660
    static let detailPadding: CGFloat = 30
    static let detailSpacing: CGFloat = 24
    static let sectionSpacing: CGFloat = 18
    static let formLabelWidth: CGFloat = 144
}

private enum SettingsPane: String, CaseIterable, Hashable, Identifiable {
    case storage
    case connections
    case processing
    case output
    case general
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .storage:
            return "Storage"
        case .connections:
            return "Connections"
        case .processing:
            return "Processing"
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
        case .storage:
            return "externaldrive.badge.wifi"
        case .connections:
            return "network"
        case .processing:
            return "slider.horizontal.3"
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
        case .storage:
            return "Configure S3 uploads and retention for files staged in the bucket."
        case .connections:
            return "Manage credentials for external services and future integrations."
        case .processing:
            return "Choose which engine handles each file type by default."
        case .output:
            return "Control where markdown files are saved and how they are named."
        case .general:
            return "Set app-wide behavior, defaults, and everyday workflow options."
        case .about:
            return "Version details, configuration access, and support information."
        }
    }
}

/// Settings content displayed inside the dedicated settings window.
struct SettingsView: View {
    /// View model providing settings data and persistence.
    @ObservedObject var viewModel: SettingsViewModel
    /// Called when the user closes the settings window.
    var onClose: () -> Void
    /// Terminates the menu bar app.
    var onQuitApp: () -> Void
    @State private var selectedPane: SettingsPane = .storage

    var body: some View {
        TabView(selection: $selectedPane) {
            Tab("Storage", systemImage: SettingsPane.storage.systemImage, value: .storage) {
                detailContent(for: .storage)
            }

            Tab("Connections", systemImage: SettingsPane.connections.systemImage, value: .connections) {
                detailContent(for: .connections)
            }

            Tab("Processing", systemImage: SettingsPane.processing.systemImage, value: .processing) {
                detailContent(for: .processing)
            }

            Tab("Output", systemImage: SettingsPane.output.systemImage, value: .output) {
                detailContent(for: .output)
            }

            Tab("General", systemImage: SettingsPane.general.systemImage, value: .general) {
                detailContent(for: .general)
            }

            Tab("About", systemImage: SettingsPane.about.systemImage, value: .about) {
                detailContent(for: .about)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar(removing: .title)
        .frame(
            minWidth: SettingsWindowDesign.minSize.width,
            minHeight: SettingsWindowDesign.minSize.height
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await viewModel.load() }
    }

    private func detailContent(for pane: SettingsPane) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsWindowDesign.detailSpacing) {
                    pageHeader(for: pane)
                    pageContent(for: pane)
                }
                .frame(maxWidth: SettingsWindowDesign.detailMaxWidth, alignment: .leading)
                .padding(SettingsWindowDesign.detailPadding)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func pageHeader(for pane: SettingsPane) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pane.title)
                .font(.system(size: 27, weight: .bold, design: .rounded))

            Text(pane.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func pageContent(for pane: SettingsPane) -> some View {
        switch pane {
        case .storage:
            storagePage
        case .connections:
            connectionsPage
        case .processing:
            processingPage
        case .output:
            outputPage
        case .general:
            generalPage
        case .about:
            aboutPage
        }
    }

    private var storagePage: some View {
        VStack(alignment: .leading, spacing: SettingsWindowDesign.sectionSpacing) {
            settingsSection("S3-Compatible Storage") {
                settingsGrid {
                    settingsRow(
                        "Endpoint URL",
                        help: "You can paste either https://host or just host; the app will normalize it to HTTPS."
                    ) {
                        TextField("https://s3.example.com", text: $viewModel.settings.s3EndpointURL)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.large)
                    }

                    settingsRow("Access Key") {
                        TextField("Access Key", text: $viewModel.settings.s3AccessKey)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.large)
                    }

                    settingsRow("Secret Key") {
                        secretField(
                            "Secret Key",
                            text: $viewModel.s3SecretKey,
                            isVisible: $viewModel.isS3SecretKeyVisible
                        )
                    }

                    settingsRow("Bucket Name") {
                        TextField("Bucket Name", text: $viewModel.settings.s3BucketName)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.large)
                    }

                    settingsRow("Region") {
                        TextField("Region", text: $viewModel.settings.s3Region)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.large)
                    }

                    settingsRow("Path Prefix") {
                        TextField("Path Prefix", text: $viewModel.settings.s3PathPrefix)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.large)
                    }

                    settingsRow("Connection Test") {
                        HStack(spacing: 10) {
                            testButton("Test", result: viewModel.s3TestResult) {
                                Task { await viewModel.testS3() }
                            }
                            testResultView(viewModel.s3TestResult)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }

            settingsSection("Retention") {
                settingsGrid {
                    settingsRow(
                        "File Retention",
                        help: "Applies to files stored in S3 after upload. Set to 0 to disable automatic cleanup."
                    ) {
                        HStack(spacing: 8) {
                            TextField(
                                "Hours",
                                value: $viewModel.settings.fileRetentionHours,
                                format: .number
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 96)

                            Text("hours")
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 0)
                        }
                        .controlSize(.large)
                    }
                }
            }
        }
    }

    private var connectionsPage: some View {
        settingsSection("Mistral API") {
            settingsGrid {
                settingsRow("API Key") {
                    secretField(
                        "API Key",
                        text: $viewModel.mistralAPIKey,
                        isVisible: $viewModel.isMistralAPIKeyVisible
                    )
                }

                settingsRow("Connection Test") {
                    HStack(spacing: 10) {
                        testButton("Test", result: viewModel.mistralTestResult) {
                            Task { await viewModel.testMistral() }
                        }
                        testResultView(viewModel.mistralTestResult)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var processingPage: some View {
        VStack(alignment: .leading, spacing: SettingsWindowDesign.sectionSpacing) {
            settingsSection("Default Providers") {
                settingsGrid {
                    settingsRow("Audio") {
                        providerModePicker(selection: $viewModel.settings.audioProviderMode)
                    }

                    settingsRow("PDF") {
                        providerModePicker(selection: $viewModel.settings.pdfProviderMode)
                    }

                    settingsRow("Image") {
                        providerModePicker(selection: $viewModel.settings.imageProviderMode)
                    }
                }
            }

            settingsSection("Apple On-Device Audio") {
                settingsGrid {
                    settingsRow(
                        "Language",
                        help: "Used only when Audio is set to Local Apple. Match this to the recording language for better recognition quality."
                    ) {
                        appleAudioLocalePicker()
                            .disabled(viewModel.settings.audioProviderMode != .localApple)
                    }
                }
            }
        }
    }

    private var outputPage: some View {
        VStack(alignment: .leading, spacing: SettingsWindowDesign.sectionSpacing) {
            settingsSection("Saving") {
                settingsGrid {
                    settingsRow(
                        "Save Folder",
                        help: "Markdown files are always saved to this folder."
                    ) {
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
                }

            }

            settingsSection("File Naming") {
                settingsGrid {
                    settingsRow(
                        "Filename Prefix",
                        help: "Optional text exposed through the {prefix} variable, for example notes- or capture-."
                    ) {
                        TextField("notes-", text: $viewModel.settings.outputFileNamePrefix)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.large)
                    }

                    settingsRow(
                        "Filename Template",
                        help: "Available variables: {originalFilename}, {fileType}, {timestamp}, {date}, {time}, {prefix}. The .md extension is added automatically."
                    ) {
                        TextField(
                            AppSettings.defaultFileNameTemplate,
                            text: $viewModel.settings.outputFileNameTemplate
                        )
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                        .font(.system(.body, design: .monospaced))
                    }

                    settingsRow("Preview") {
                        Text(viewModel.outputFileNamePreview)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var generalPage: some View {
        VStack(alignment: .leading, spacing: SettingsWindowDesign.sectionSpacing) {
            settingsSection("Behavior") {
                settingsToggleRow(
                    help: "Also places the generated markdown on the clipboard after each run."
                ) {
                    Toggle("Copy markdown to clipboard", isOn: $viewModel.settings.copyToClipboard)
                }
            }

            settingsSection("Startup") {
                settingsToggleRow(
                    help: "Starts the menu bar app automatically when you sign in to macOS."
                ) {
                    Toggle("Launch at Login", isOn: $viewModel.settings.launchAtLogin)
                }
            }
        }
    }

    private var aboutPage: some View {
        VStack(alignment: .leading, spacing: SettingsWindowDesign.sectionSpacing) {
            settingsSection("Application") {
                settingsGrid {
                    settingsRow("Version") {
                        Text(appVersionSummary)
                            .textSelection(.enabled)
                    }

                    settingsRow("Bundle ID") {
                        Text(Bundle.main.bundleIdentifier ?? AppIdentity.bundleIdentifier)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            settingsSection("Configuration") {
                settingsGrid {
                    settingsRow(
                        "Passwords",
                        help: "Mistral API keys and S3 secret keys are stored in Keychain only and never written to config.toml."
                    ) {
                        Text("Stored securely in Keychain")
                            .foregroundStyle(.secondary)
                    }

                    settingsRow("Config File") {
                        Text(configFileURL.path())
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    settingsRow("Actions") {
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
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let error = viewModel.error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else {
                Text("Changes apply when you save.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Quit trnscrb") {
                onQuitApp()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .pointingHandCursor()

            saveButton
        }
        .padding(.horizontal, SettingsWindowDesign.detailPadding)
        .padding(.vertical, 14)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var saveButton: some View {
        Button("Save") {
            Task {
                let didSave: Bool = await viewModel.save()
                if didSave {
                    onClose()
                }
            }
        }
        .buttonStyle(.glassProminent)
        .tint(.accentColor)
        .keyboardShortcut("s", modifiers: .command)
        .pointingHandCursor()
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GroupBox {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(title)
                .font(.headline)
        }
        .groupBoxStyle(.automatic)
    }

    private var appVersionSummary: String {
        let shortVersion: String = {
            guard let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                  !raw.isEmpty,
                  !raw.contains("$")
            else {
                return "0.1.1"
            }
            return raw
        }()

        guard let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              !buildNumber.isEmpty,
              !buildNumber.contains("$")
        else {
            return shortVersion
        }

        return "\(shortVersion) (\(buildNumber))"
    }

    private var configFileURL: URL {
        TOMLConfigManager.defaultConfigFileURL
    }

    private func settingsGrid<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 16) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsRow<Content: View>(
        _ title: String,
        help: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GridRow(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: SettingsWindowDesign.formLabelWidth, alignment: .trailing)

            VStack(alignment: .leading, spacing: 6) {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let help {
                    Text(help)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func settingsToggleRow<Content: View>(
        help: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            content()

            if let help {
                Text(help)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
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
            Text("Local Apple").tag(ProviderMode.localApple)
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.large)
    }

    private func appleAudioLocalePicker() -> some View {
        Picker("", selection: $viewModel.settings.appleAudioLocaleIdentifier) {
            ForEach(appleAudioLocaleOptions) { option in
                Text(option.label).tag(option.identifier)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.large)
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
            viewModel.settings.saveFolderPath = selectedURL.standardizedFileURL.path()
        }
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
