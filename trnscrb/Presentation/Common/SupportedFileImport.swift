import AppKit
import Foundation
import UniformTypeIdentifiers

enum SupportedFileImport {
    static let pasteboardContentTypes: [UTType] = [.fileURL]

    static func containsSupportedFile(_ urls: [URL]) -> Bool {
        urls.contains(where: isSupportedFile)
    }

    static func isSupportedFile(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        return FileType.from(extension: url.pathExtension.lowercased()) != nil
    }

    static func loadFileURLs(
        from providers: [NSItemProvider],
        completion: @escaping ([URL]) -> Void
    ) {
        let urlProviders: [NSItemProvider] = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !urlProviders.isEmpty else {
            completion([])
            return
        }

        let collectedURLs: LockedURLStore = LockedURLStore()
        let group: DispatchGroup = DispatchGroup()

        for provider in urlProviders {
            group.enter()
            _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                defer { group.leave() }
                guard let url = object as? URL, url.isFileURL else { return }
                collectedURLs.append(url)
            }
        }

        group.notify(queue: .main) {
            completion(collectedURLs.snapshot())
        }
    }
}

private final class LockedURLStore: @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private var values: [URL] = []

    func append(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        values.append(url)
    }

    func snapshot() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}
