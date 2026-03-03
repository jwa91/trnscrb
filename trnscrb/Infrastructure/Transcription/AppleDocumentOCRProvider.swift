import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Vision

/// Performs local OCR for PDFs and images using Apple frameworks.
///
/// This provider is gated to macOS 26+ so local mode remains Tahoe-only.
public struct AppleDocumentOCRProvider: TranscriptionGateway {
    public let providerMode: ProviderMode = .localApple
    public let sourceKind: TranscriptionSourceKind = .localFile
    public var supportedExtensions: Set<String> {
        FileType.pdfExtensions.union(FileType.imageExtensions)
    }

    public init() {}

    public func process(sourceURL: URL) async throws -> String {
        guard sourceURL.isFileURL else {
            throw LocalProviderError.localFileRequired
        }
        guard #available(macOS 26, *) else {
            throw LocalProviderError.localModeUnavailable
        }

        let ext: String = sourceURL.pathExtension.lowercased()
        if FileType.pdfExtensions.contains(ext) {
            return try processPDF(sourceURL)
        }
        if FileType.imageExtensions.contains(ext) {
            return try processImage(sourceURL)
        }
        throw LocalProviderError.unreadableInput("Unsupported local document extension: .\(ext)")
    }

    private func processPDF(_ fileURL: URL) throws -> String {
        guard let document: PDFDocument = PDFDocument(url: fileURL) else {
            throw LocalProviderError.unreadableInput("Could not open PDF.")
        }

        var markdownPages: [String] = []
        for pageIndex in 0..<document.pageCount {
            guard let page: PDFPage = document.page(at: pageIndex) else {
                continue
            }

            let extracted: String
            let directText: String = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !directText.isEmpty {
                extracted = directText
            } else if let image: CGImage = rasterizedImage(for: page) {
                extracted = try recognizeText(in: image)
            } else {
                extracted = ""
            }

            let normalized: String = extracted.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            markdownPages.append("## Page \(pageIndex + 1)\n\n\(normalized)")
        }

        guard !markdownPages.isEmpty else {
            throw LocalProviderError.noRecognizedContent
        }
        return markdownPages.joined(separator: "\n\n")
    }

    private func processImage(_ fileURL: URL) throws -> String {
        guard let source: CGImageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let image: CGImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw LocalProviderError.unreadableInput("Could not decode image.")
        }

        let text: String = try recognizeText(in: image)
        let normalized: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw LocalProviderError.noRecognizedContent
        }
        return normalized
    }

    private func recognizeText(in image: CGImage) throws -> String {
        let request: VNRecognizeTextRequest = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US", "nl-NL"]

        let handler: VNImageRequestHandler = VNImageRequestHandler(cgImage: image)
        do {
            try handler.perform([request])
        } catch {
            throw LocalProviderError.ocrFailed(error.localizedDescription)
        }

        let observations: [VNRecognizedTextObservation] = request.results ?? []
        let lines: [String] = observations.compactMap { observation in
            observation.topCandidates(1).first?.string
        }
        return lines.joined(separator: "\n")
    }

    private func rasterizedImage(for page: PDFPage) -> CGImage? {
        let bounds: CGRect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2
        let width: Int = max(Int(bounds.width * scale), 1)
        let height: Int = max(Int(bounds.height * scale), 1)

        guard let context: CGContext = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }
}
