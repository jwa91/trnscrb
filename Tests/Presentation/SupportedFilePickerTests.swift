import Testing
import UniformTypeIdentifiers

@testable import trnscrb

struct SupportedFilePickerTests {
    @Test func configurationMatchesExpectedFileSelectionBehavior() {
        let configuration: SupportedFilePicker.Configuration = SupportedFilePicker.configuration

        #expect(configuration.allowsMultipleSelection)
        #expect(!configuration.canChooseDirectories)

        let expectedTypes: Set<UTType> = Set(
            FileType.allSupported.compactMap { extensionName in
                UTType(filenameExtension: extensionName)
            }
        )
        #expect(Set(configuration.allowedContentTypes) == expectedTypes)
    }
}
