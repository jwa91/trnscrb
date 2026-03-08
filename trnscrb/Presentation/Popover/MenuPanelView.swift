import SwiftUI
import UniformTypeIdentifiers

/// Root view displayed inside the attached menu bar panel.
///
/// Shows the drop zone when idle and the job list while processing.
/// The entire view is always a valid drop target.
struct MenuPanelView: View {
    /// Tracks whether a file picker panel is currently open.
    @ObservedObject var filePickerPresentationModel: FilePickerPresentationModel
    /// View model for the job queue and processing.
    @ObservedObject var jobListViewModel: JobListViewModel
    /// Opens the dedicated settings window.
    var onOpenSettings: () -> Void
    /// Called when the panel should close.
    var onClose: () -> Void

    var body: some View {
        mainContent
        .onChange(of: jobListViewModel.shouldOpenSettings) { _, shouldOpenSettings in
            guard shouldOpenSettings else { return }
            onOpenSettings()
            jobListViewModel.consumeSettingsNavigation()
        }
    }

    /// Main content shown when settings is not active.
    private var mainContent: some View {
        let layout: PopoverContentLayout = PopoverContentLayout(
            activeJobCount: jobListViewModel.activeJobs.count,
            completedJobCount: jobListViewModel.completedJobs.count
        )
        let hasJobs: Bool = !jobListViewModel.activeJobs.isEmpty || !jobListViewModel.completedJobs.isEmpty

        return VStack(spacing: 0) {
            header
            VStack(spacing: PopoverDesign.sectionSpacing) {
                if let error: String = jobListViewModel.configurationError {
                    banner(
                        error,
                        icon: "exclamationmark.triangle",
                        color: .orange,
                        onDismiss: jobListViewModel.clearConfigurationError
                    )
                }

                if let offlineStatusMessage: String = jobListViewModel.offlineStatusMessage {
                    banner(
                        offlineStatusMessage,
                        icon: "wifi.slash",
                        color: .orange,
                        onDismiss: jobListViewModel.clearOfflineStatus
                    )
                }

                if let dropError: String = jobListViewModel.dropError {
                    banner(
                        dropError,
                        icon: "xmark.circle",
                        color: .red,
                        onDismiss: jobListViewModel.clearDropError
                    )
                }

                switch layout.dropZoneMode {
                case .full:
                    DropZoneView(
                        onDrop: jobListViewModel.processFiles,
                        onSelectFiles: openFilePicker,
                        isFilePickerPresented: filePickerPresentationModel.isPresenting
                    )
                case .compact:
                    DropZoneView(
                        onDrop: jobListViewModel.processFiles,
                        onSelectFiles: openFilePicker,
                        mode: .compact,
                        isFilePickerPresented: filePickerPresentationModel.isPresenting
                    )
                case .hidden:
                    EmptyView()
                }

                if hasJobs {
                    JobListView(viewModel: jobListViewModel)
                        .frame(maxHeight: .infinity, alignment: .top)
                } else {
                    Spacer(minLength: 0)
                }
            }
            .padding(PopoverDesign.contentPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(
            width: PopoverDesign.panelSize.width,
            height: PopoverDesign.panelSize.height
        )
        .background(PopoverDesign.surfaceBackground)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    private var header: some View {
        PopoverChromeBar(showsDivider: false) {
            AppBrandView()
        } trailing: {
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    ChromeIconButton(
                        systemName: "gearshape",
                        title: "Settings",
                        action: onOpenSettings
                    )
                    ChromeIconButton(
                        systemName: "power",
                        title: "Quit trnscrb",
                        action: { NSApp.terminate(nil) },
                        keyboardShortcut: KeyboardShortcut("q", modifiers: .command)
                    )
                    ChromeIconButton(
                        systemName: "xmark",
                        title: "Close",
                        action: onClose,
                        keyboardShortcut: KeyboardShortcut("w", modifiers: .command)
                    )
                }
            }
        }
    }

    /// Banner shown for non-fatal user-facing status and validation messages.
    private func banner(
        _ message: String,
        icon: String,
        color: Color,
        onDismiss: @escaping () -> Void
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(message)
                .font(PopoverDesign.secondaryTextFont)
                .lineLimit(2)
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .pointingHandCursor()
        }
        .padding(12)
        .background(
            RoundedRectangle(
                cornerRadius: PopoverDesign.cardCornerRadius,
                style: .continuous
            )
            .fill(color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: PopoverDesign.cardCornerRadius,
                style: .continuous
            )
            .strokeBorder(color.opacity(0.18), lineWidth: 1)
        )
    }

    /// Handles drops on the entire panel surface.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !filePickerPresentationModel.isPresenting else { return false }
        SupportedFileImport.loadFileURLs(from: providers) { urls in
            if !urls.isEmpty {
                jobListViewModel.processFiles(urls)
            }
        }
        return true
    }

    private func openFilePicker() {
        let urls: [URL] = filePickerPresentationModel.pickFiles()
        guard !urls.isEmpty else { return }
        jobListViewModel.processFiles(urls)
    }
}
