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
        if showSettings {
            SettingsView(
                viewModel: settingsViewModel,
                onBack: { showSettings = false }
            )
        } else {
            mainContent
        }
    }

    /// Main content shown when settings is not active.
    private var mainContent: some View {
        VStack(spacing: 0) {
            if let error: String = jobListViewModel.configurationError {
                configurationBanner(error)
            }

            if jobListViewModel.activeJobs.isEmpty && jobListViewModel.completedJobs.isEmpty {
                DropZoneView(onDrop: jobListViewModel.processFiles)
            } else {
                if jobListViewModel.activeJobs.isEmpty {
                    DropZoneView(onDrop: jobListViewModel.processFiles)
                        .frame(height: 100)
                }
                JobListView(viewModel: jobListViewModel)
            }

            Spacer(minLength: 0)
            Divider()
            footer
        }
        .frame(width: 320, height: 360)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    /// Banner shown when S3 or API key is not configured.
    private func configurationBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .lineLimit(2)
            Spacer()
            Button("Settings") {
                showSettings = true
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(8)
        .background(.orange.opacity(0.1))
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
        // nonisolated(unsafe): access is serialized by the DispatchGroup —
        // all writes happen before group.notify fires on main.
        nonisolated(unsafe) var urls: [URL] = []
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
                    urls.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            let supported: [URL] = urls.filter {
                FileType.allSupported.contains($0.pathExtension.lowercased())
            }
            if !supported.isEmpty {
                jobListViewModel.processFiles(supported)
            }
        }
        return true
    }
}
