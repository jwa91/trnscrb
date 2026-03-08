import Foundation

/// The result of processing a file through the transcription/OCR pipeline.
public struct TranscriptionResult: Sendable, Equatable {
    /// The markdown content produced by transcription or OCR.
    public let markdown: String
    /// The original file name that was processed.
    public let sourceFileName: String
    /// The type of file that was processed.
    public let sourceFileType: FileType
    /// Non-fatal mirroring warnings produced after processing succeeded.
    public let mirrorWarnings: [String]
    /// Non-fatal delivery warnings produced after transcription succeeded.
    public let deliveryWarnings: [String]
    /// Local file URL when markdown was saved to disk.
    public let savedFileURL: URL?
    /// Externally reachable source URL created for remote processing or mirroring.
    public let remoteSourceURL: URL?

    /// Creates a transcription result.
    public init(
        markdown: String,
        sourceFileName: String,
        sourceFileType: FileType,
        mirrorWarnings: [String] = [],
        deliveryWarnings: [String] = [],
        savedFileURL: URL? = nil,
        remoteSourceURL: URL? = nil
    ) {
        self.markdown = markdown
        self.sourceFileName = sourceFileName
        self.sourceFileType = sourceFileType
        self.mirrorWarnings = mirrorWarnings
        self.deliveryWarnings = deliveryWarnings
        self.savedFileURL = savedFileURL
        self.remoteSourceURL = remoteSourceURL
    }
}
