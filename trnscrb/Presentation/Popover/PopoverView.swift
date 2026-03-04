import SwiftUI
import UniformTypeIdentifiers

/// Root view displayed inside the menu bar popover.
///
/// Shows the drop zone when idle, job list when processing, and settings
/// panel when toggled. The entire view is always a valid drop target.
struct PopoverView: View {
    /// Controls whether the settings panel is visible.
    @State private var showSettings: Bool = false
    /// View model for the settings panel.
    @ObservedObject var settingsViewModel: SettingsViewModel
    /// View model for the job queue and processing.
    @ObservedObject var jobListViewModel: JobListViewModel
    /// Called when the popover should close.
    var onClose: () -> Void

    var body: some View {
        Group {
            if showSettings {
                SettingsView(
                    viewModel: settingsViewModel,
                    onBack: { showSettings = false },
                    onClose: onClose
                )
            } else {
                mainContent
            }
        }
        .onChange(of: jobListViewModel.shouldOpenSettings) { _, shouldOpenSettings in
            guard shouldOpenSettings else { return }
            showSettings = true
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
                    DropZoneView(onDrop: jobListViewModel.processFiles)
                case .compact:
                    DropZoneView(
                        onDrop: jobListViewModel.processFiles,
                        mode: .compact
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
            width: PopoverDesign.popoverSize.width,
            height: PopoverDesign.popoverSize.height
        )
        .background(PopoverDesign.surfaceBackground)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    private var header: some View {
        PopoverChromeBar {
            AppBrandView()
        } trailing: {
            HStack(spacing: 6) {
                ChromeIconButton(
                    systemName: "folder",
                    title: "Open Save Folder",
                    action: {
                        Task {
                            await jobListViewModel.openConfiguredSaveFolder()
                        }
                    }
                )
                ChromeIconButton(
                    systemName: "gearshape",
                    title: "Settings",
                    action: { showSettings = true }
                )
                ChromeIconButton(
                    systemName: "xmark",
                    title: "Close",
                    action: onClose
                )
            }
        }
    }

    /// Banner shown when S3 or API key is not configured.
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

    /// Handles drops on the entire popover surface.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let collectedURLs: LockedURLStore = LockedURLStore()
        let group: DispatchGroup = DispatchGroup()

        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
                continue
            }
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                defer { group.leave() }
                if let data = item as? Data,
                   let url: URL = URL(dataRepresentation: data, relativeTo: nil) {
                    collectedURLs.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            let urls: [URL] = collectedURLs.snapshot()
            if !urls.isEmpty {
                jobListViewModel.processFiles(urls)
            }
        }
        return true
    }
}
/// Thread-safe URL collector for async item-provider callbacks.
private final class LockedURLStore: @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private var values: [URL] = []

    func append(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        values.append(url)
    }

    func snapshot() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}
