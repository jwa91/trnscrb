import Foundation
import Testing

@testable import trnscrb

@MainActor
struct FilePickerPresentationModelTests {
    @Test func pickFilesMarksPresentationStateDuringPickerExecution() {
        var model: FilePickerPresentationModel!
        var observedPresentationState: Bool = false
        let expectedURL: URL = URL(filePath: "/tmp/test.mp3")

        model = FilePickerPresentationModel(picker: {
            observedPresentationState = model.isPresenting
            return [expectedURL]
        })

        let urls: [URL] = model.pickFiles()

        #expect(observedPresentationState)
        #expect(!model.isPresenting)
        #expect(urls == [expectedURL])
    }

    @Test func pickFilesIgnoresReentrantRequestsWhilePanelIsOpen() {
        var model: FilePickerPresentationModel!
        var nestedURLs: [URL] = []

        model = FilePickerPresentationModel(picker: {
            nestedURLs = model.pickFiles()
            return [URL(filePath: "/tmp/test.mp3")]
        })

        let urls: [URL] = model.pickFiles()

        #expect(urls.count == 1)
        #expect(nestedURLs.isEmpty)
        #expect(!model.isPresenting)
    }
}
