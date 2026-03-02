import Foundation

/// The result of processing a file through the transcription/OCR pipeline.
public struct TranscriptionResult: Sendable, Equatable {
    /// The markdown content produced by transcription or OCR.
    public let markdown: String
    /// The original file name that was processed.
    public let sourceFileName: String
    /// The type of file that was processed.
    public let sourceFileType: FileType
    /// Non-fatal delivery warnings produced after transcription succeeded.
    public let deliveryWarnings: [String]

    /// Creates a transcription result.
    public init(
        markdown: String,
        sourceFileName: String,
        sourceFileType: FileType,
        deliveryWarnings: [String] = []
    ) {
        self.markdown = markdown
        self.sourceFileName = sourceFileName
        self.sourceFileType = sourceFileType
        self.deliveryWarnings = deliveryWarnings
    }
}
