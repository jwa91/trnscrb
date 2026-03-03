import Foundation

/// Abstracts transcription and OCR processing.
///
/// Both audio transcription (Voxtral) and document/image OCR conform
/// to this protocol. The `ProcessFileUseCase` routes by `FileType`
/// without knowing which API is called.
public protocol TranscriptionGateway: Sendable {
    /// The file extensions this provider can process.
    var supportedExtensions: Set<String> { get }

    /// Processes a file at the given URL and returns markdown.
    /// - Parameter sourceURL: Source the provider can read directly. Audio providers
    ///   may require a local file URL, while OCR providers can use a presigned URL.
    /// - Returns: Markdown string produced by transcription or OCR.
    func process(sourceURL: URL) async throws -> String
}
