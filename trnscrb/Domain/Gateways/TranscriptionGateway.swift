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
    /// - Parameter sourceURL: Presigned URL pointing to the file in storage.
    /// - Returns: Markdown string produced by transcription or OCR.
    func process(sourceURL: URL) async throws -> String
}
