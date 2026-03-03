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
            .padding(innerPadding)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(innerBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        borderColor,
                        style: StrokeStyle(lineWidth: borderLineWidth, dash: [6])
                    )
            )
            .padding(outerPadding)
            .frame(maxWidth: .infinity)
            .frame(minHeight: mode == .full ? 180 : nil)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(outerBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(outerBorderColor, lineWidth: 1)
            )
            .padding(.horizontal, 10)
            .padding(.vertical, mode == .full ? 10 : 6)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .pointingHandCursor()
            .onTapGesture {
                openFilePicker()
            }
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
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 32))
                    .foregroundStyle(isHovered || isTargeted ? Color.accentColor : Color.secondary)
                Text("Drop files here")
                    .font(.headline)
                Text("or click to choose audio, PDFs, and images")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                fileTypeHints
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        case .compact:
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 18))
                    .foregroundStyle(isHovered || isTargeted ? Color.accentColor : Color.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Add more files")
                        .font(.caption.weight(.semibold))
                    Text("Drop here or click to choose audio, PDFs, and images")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
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

    private var innerPadding: EdgeInsets {
        switch mode {
        case .full:
            return EdgeInsets(top: 14, leading: 12, bottom: 14, trailing: 12)
        case .compact:
            return EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        }
    }

    private var outerPadding: EdgeInsets {
        switch mode {
        case .full:
            return EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        case .compact:
            return EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        }
    }

    private var innerBackgroundColor: Color {
        if isTargeted {
            return Color.accentColor.opacity(0.1)
        }
        if isHovered {
            return Color.primary.opacity(0.03)
        }
        return .clear
    }

    private var outerBackgroundColor: Color {
        if isTargeted {
            return Color.accentColor.opacity(0.05)
        }
        return Color.primary.opacity(0.02)
    }

    private var outerBorderColor: Color {
        if isTargeted {
            return Color.accentColor.opacity(0.45)
        }
        return Color.secondary.opacity(0.22)
    }

    private var borderColor: Color {
        if isTargeted {
            return Color.accentColor
        }
        if isHovered {
            return Color.secondary.opacity(0.6)
        }
        return Color.secondary.opacity(0.45)
    }

    private var borderLineWidth: CGFloat {
        isTargeted ? 2 : 1.2
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
