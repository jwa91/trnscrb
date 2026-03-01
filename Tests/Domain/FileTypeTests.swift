import Testing

@testable import trnscrb

struct FileTypeTests {
    @Test func audioExtensions() {
        let audioExts: [String] = ["mp3", "wav", "m4a", "ogg", "flac", "webm", "mp4"]
        for ext in audioExts {
            #expect(FileType.from(extension: ext) == .audio, "Expected \(ext) to map to .audio")
        }
    }

    @Test func pdfExtension() {
        #expect(FileType.from(extension: "pdf") == .pdf)
    }

    @Test func imageExtensions() {
        let imageExts: [String] = ["png", "jpg", "jpeg", "heic", "tiff", "webp"]
        for ext in imageExts {
            #expect(FileType.from(extension: ext) == .image, "Expected \(ext) to map to .image")
        }
    }

    @Test func unsupportedExtensionReturnsNil() {
        #expect(FileType.from(extension: "xyz") == nil)
        #expect(FileType.from(extension: "doc") == nil)
        #expect(FileType.from(extension: "") == nil)
    }

    @Test func caseInsensitive() {
        #expect(FileType.from(extension: "MP3") == .audio)
        #expect(FileType.from(extension: "Pdf") == .pdf)
        #expect(FileType.from(extension: "PNG") == .image)
        #expect(FileType.from(extension: "HEIC") == .image)
    }

    @Test func allSupportedContainsEveryExtension() {
        let expected: Set<String> = [
            "mp3", "wav", "m4a", "ogg", "flac", "webm", "mp4",
            "pdf",
            "png", "jpg", "jpeg", "heic", "tiff", "webp"
        ]
        #expect(FileType.allSupported == expected)
    }
}
