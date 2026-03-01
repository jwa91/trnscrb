import Foundation

/// Represents the category of a file being processed.
public enum FileType: Sendable, Equatable {
    /// Audio files (mp3, wav, m4a, ogg, flac, webm, mp4).
    case audio
    /// PDF documents.
    case pdf
    /// Image files (png, jpg, jpeg, heic, tiff, webp).
    case image

    /// File extensions accepted for audio transcription.
    public static let audioExtensions: Set<String> = [
        "mp3", "wav", "m4a", "ogg", "flac", "webm", "mp4"
    ]

    /// File extensions accepted for PDF processing.
    public static let pdfExtensions: Set<String> = ["pdf"]

    /// File extensions accepted for image OCR.
    public static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "tiff", "webp"
    ]

    /// All supported file extensions across all types.
    public static let allSupported: Set<String> =
        audioExtensions.union(pdfExtensions).union(imageExtensions)

    /// Determines the file type from a file extension.
    /// - Parameter ext: The file extension (without leading dot), case-insensitive.
    /// - Returns: The matching `FileType`, or `nil` if unsupported.
    public static func from(extension ext: String) -> FileType? {
        let lowered: String = ext.lowercased()
        if audioExtensions.contains(lowered) { return .audio }
        if pdfExtensions.contains(lowered) { return .pdf }
        if imageExtensions.contains(lowered) { return .image }
        return nil
    }
}
