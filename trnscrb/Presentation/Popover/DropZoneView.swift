import SwiftUI
import UniformTypeIdentifiers

/// A drop zone that accepts files via drag-and-drop or a file picker fallback.
///
/// Shows a visual target area with hover feedback. Validates file types
/// using `FileType.allSupported` and calls `onDrop` with valid URLs.
struct DropZoneView: View {
    enum Mode {
        case full
        case compact
    }

    /// Called with the URLs of dropped/selected files.
    var onDrop: ([URL]) -> Void
    /// Layout variant for the idle or inline uploader state.
    var mode: Mode = .full
    /// Tracks whether a drag is hovering over the zone.
    @State private var isTargeted: Bool = false
    /// Tracks whether the pointer is hovering over the zone.
    @State private var isHovered: Bool = false

    var body: some View {
        content
        .frame(maxWidth: .infinity, maxHeight: mode == .full ? .infinity : nil)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
                .padding(8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.clear,
                    style: StrokeStyle(lineWidth: 2, dash: [6])
                )
                .padding(8)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .pointingHandCursor()
        .onHover { isHovered = $0 }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .full:
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 32))
                    .foregroundStyle(isHovered || isTargeted ? Color.accentColor : Color.secondary)
                Text("Drop files here")
                    .font(.headline)
                Text("or drag onto the menu bar icon")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                chooseFilesButton
                    .padding(.top, 4)
                fileTypeHints
                Spacer()
            }
        case .compact:
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 18))
                    .foregroundStyle(isHovered || isTargeted ? Color.accentColor : Color.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Add more files")
                        .font(.caption.weight(.semibold))
                    Text("Drop here or choose audio, PDFs, and images")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)
                chooseFilesButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private var chooseFilesButton: some View {
        DropZoneChooseFilesButton(
            title: mode == .full ? "Choose Files\u{2026}" : "Choose\u{2026}",
            action: openFilePicker
        )
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

    private var backgroundColor: Color {
        if isTargeted {
            return Color.accentColor.opacity(0.12)
        }
        if isHovered {
            return Color.primary.opacity(0.04)
        }
        return .clear
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
        let urls: [URL] = SupportedFilePicker.pickFiles()
        guard !urls.isEmpty else { return }
        onDrop(urls)
    }
}

private struct DropZoneChooseFilesButton: View {
    let title: String
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .foregroundStyle(isHovered ? Color.accentColor : Color.accentColor.opacity(0.88))
                .underline(isHovered)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { isHovered = $0 }
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
