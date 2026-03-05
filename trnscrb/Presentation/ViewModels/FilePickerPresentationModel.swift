import Foundation

@MainActor
final class FilePickerPresentationModel: ObservableObject {
    private let picker: @MainActor () -> [URL]
    @Published private(set) var isPresenting: Bool = false

    init(picker: @escaping @MainActor () -> [URL] = SupportedFilePicker.pickFiles) {
        self.picker = picker
    }

    func pickFiles() -> [URL] {
        guard !isPresenting else { return [] }

        isPresenting = true
        defer { isPresenting = false }
        return picker()
    }
}
