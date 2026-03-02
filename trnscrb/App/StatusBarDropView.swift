import AppKit

/// Transparent drop target overlaid on the status bar button.
///
/// Accepts file URL drops and forwards URLs to the provided callback.
/// File-type validation happens in the view model so unsupported drops can
/// produce user-visible errors instead of being silently ignored.
/// Does not interfere
/// with click handling — only drag-and-drop events are intercepted.
final class StatusBarDropView: NSView {
    /// Called with validated file URLs when a drop is accepted.
    var onDrop: (([URL]) -> Void)?
    /// Called when a valid drag enters the view (for icon highlight).
    var onDragEntered: (() -> Void)?
    /// Called when the drag exits the view or the drop completes.
    var onDragExited: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasFileURLs(sender) else { return [] }
        onDragEntered?()
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasFileURLs(sender) else { return [] }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragExited?()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDragExited?()
        guard let urls: [URL] = extractFileURLs(from: sender), !urls.isEmpty else {
            return false
        }
        onDrop?(urls)
        return true
    }

    // MARK: - Pass through mouse events to the button underneath

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    // MARK: - Private

    /// Checks whether the drag contains at least one file URL.
    private func hasFileURLs(_ sender: NSDraggingInfo) -> Bool {
        guard let urls: [URL] = extractFileURLs(from: sender) else { return false }
        return !urls.isEmpty
    }

    /// Extracts file URLs from a dragging info pasteboard.
    private func extractFileURLs(from sender: NSDraggingInfo) -> [URL]? {
        sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
    }
}
