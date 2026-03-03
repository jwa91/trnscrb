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

    var body: some View {
        Group {
            if showSettings {
                SettingsView(
                    viewModel: settingsViewModel,
                    onBack: { showSettings = false }
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

        return VStack(spacing: 0) {
            if let error: String = jobListViewModel.configurationError {
                banner(
                    error,
                    icon: "exclamationmark.triangle",
                    color: .orange,
                    showSettingsButton: true,
                    onDismiss: jobListViewModel.clearConfigurationError
                )
            }

            if let dropError: String = jobListViewModel.dropError {
                banner(
                    dropError,
                    icon: "xmark.circle",
                    color: .red,
                    showSettingsButton: false,
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

            if !jobListViewModel.activeJobs.isEmpty || !jobListViewModel.completedJobs.isEmpty {
                JobListView(viewModel: jobListViewModel)
            }

            Spacer(minLength: 0)
            Divider()
            footer
        }
        .frame(width: 320, height: 480)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    /// Banner shown when S3 or API key is not configured.
    private func banner(
        _ message: String,
        icon: String,
        color: Color,
        showSettingsButton: Bool,
        onDismiss: @escaping () -> Void
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(message)
                .font(.caption)
                .lineLimit(2)
            Spacer()
            if showSettingsButton {
                Button("Settings") {
                    showSettings = true
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(8)
        .background(color.opacity(0.1))
    }

    /// Footer with gear icon.
    private var footer: some View {
        HStack {
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gear")
                    .font(.system(size: 14))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
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
