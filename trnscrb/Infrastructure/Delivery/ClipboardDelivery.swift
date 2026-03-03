import AppKit

/// Delivers transcription results by copying markdown to the system clipboard.
public struct ClipboardDelivery: DeliveryGateway {
    /// Creates a clipboard delivery handler.
    public init() {}

    /// Copies the markdown content to the system clipboard.
    public func deliver(result: TranscriptionResult) async throws -> DeliveryReport {
        let pasteboard: NSPasteboard = .general
        pasteboard.clearContents()
        pasteboard.setString(result.markdown, forType: .string)
        return DeliveryReport()
    }
}
