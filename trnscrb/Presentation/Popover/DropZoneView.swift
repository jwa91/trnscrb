import SwiftUI
import UniformTypeIdentifiers

/// A drop zone that accepts files via drag-and-drop or a file picker fallback.
///
/// Shows a visual target area with hover feedback. Validates file types
/// using `FileType.allSupported` and calls `onDrop` with valid URLs.
struct DropZoneView: View {
    /// Called with the URLs of dropped/selected files.
    var onDrop: ([URL]) -> Void
    /// Tracks whether a drag is hovering over the zone.
    @State private var isTargeted: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 32))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
            Text("Drop files here")
                .font(.headline)
            Text("or drag onto the menu bar icon")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Choose Files\u{2026}") {
                openFilePicker()
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .padding(.top, 4)
            fileTypeHints
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.clear,
                    style: StrokeStyle(lineWidth: 2, dash: [6])
                )
                .padding(8)
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
    }

    /// Compact listing of supported file types grouped by category.
    private var fileTypeHints: some View {
        VStack(spacing: 2) {
            Text("Audio: \(FileType.audioExtensions.sorted().joined(separator: ", "))")
            Text("PDF \u{2022} Images: \(FileType.imageExtensions.sorted().joined(separator: ", "))")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.top, 8)
    }

    /// Extracts file URLs from drop providers and calls onDrop.
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
                onDrop(urls)
            }
        }
        return true
    }

    /// Opens a macOS file picker dialog for selecting files.
    private func openFilePicker() {
        let panel: NSOpenPanel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        let extensions: [UTType] = FileType.allSupported.compactMap { ext in
            UTType(filenameExtension: ext)
        }
        panel.allowedContentTypes = extensions
        panel.begin { response in
            if response == .OK {
                onDrop(panel.urls)
            }
        }
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
