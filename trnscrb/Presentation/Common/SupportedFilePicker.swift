import AppKit
import UniformTypeIdentifiers

enum SupportedFilePicker {
    struct Configuration {
        let allowsMultipleSelection: Bool
        let canChooseDirectories: Bool
        let allowedContentTypes: [UTType]
    }

    static let configuration: Configuration = Configuration(
        allowsMultipleSelection: true,
        canChooseDirectories: false,
        allowedContentTypes: FileType.allSupported
            .sorted()
            .compactMap { extensionName in
                UTType(filenameExtension: extensionName)
            }
    )

    @MainActor
    static func pickFiles() -> [URL] {
        NSApp.activate(ignoringOtherApps: true)

        let panel: NSOpenPanel = NSOpenPanel()
        panel.allowsMultipleSelection = configuration.allowsMultipleSelection
        panel.canChooseDirectories = configuration.canChooseDirectories
        panel.canChooseFiles = true
        panel.allowedContentTypes = configuration.allowedContentTypes

        guard panel.runModal() == .OK else { return [] }
        return panel.urls
    }
}
