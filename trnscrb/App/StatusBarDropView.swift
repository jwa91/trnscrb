import AppKit

/// Transparent drop target overlaid on the status bar button.
///
/// Accepts file URL drops, validates against `FileType.allSupported`,
/// and forwards valid URLs to the provided callback. Does not interfere
/// with click handling — only drag-and-drop events are intercepted.
final class StatusBarDropView: NSView {
    /// Called with validated file URLs when a drop is accepted.
    var onDrop: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasValidFiles(sender) else { return [] }
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasValidFiles(sender) else { return [] }
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls: [URL] = extractFileURLs(from: sender), !urls.isEmpty else {
            return false
        }
        let supported: [URL] = urls.filter {
            FileType.allSupported.contains($0.pathExtension.lowercased())
        }
        guard !supported.isEmpty else { return false }
        onDrop?(supported)
        return true
    }

    // MARK: - Pass through mouse events to the button underneath

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    // MARK: - Private

    /// Checks whether the drag contains at least one supported file.
    private func hasValidFiles(_ sender: NSDraggingInfo) -> Bool {
        guard let urls: [URL] = extractFileURLs(from: sender) else { return false }
        return urls.contains { FileType.allSupported.contains($0.pathExtension.lowercased()) }
    }

    /// Extracts file URLs from a dragging info pasteboard.
    private func extractFileURLs(from sender: NSDraggingInfo) -> [URL]? {
        sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
    }
}
