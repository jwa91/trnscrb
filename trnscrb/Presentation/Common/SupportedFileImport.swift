@preconcurrency import AppKit
import Foundation
import UniformTypeIdentifiers

enum SupportedFileImport {
    static let pasteboardContentTypes: [UTType] = [.fileURL]
    private static let materializedImportDirectoryName: String = "trnscrb-imports"

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

        for (index, provider) in urlProviders.enumerated() {
            group.enter()
            loadStableFileURL(from: provider) { url in
                defer { group.leave() }
                guard let url else { return }
                collectedURLs.append(url, at: index)
            }
        }

        group.notify(queue: .main) {
            completion(collectedURLs.snapshot())
        }
    }

    private static func loadStableFileURL(
        from provider: NSItemProvider,
        completion: @escaping (URL?) -> Void
    ) {
        let providerBox: ItemProviderBox = ItemProviderBox(provider)
        let completionBox: OptionalURLCompletionBox = OptionalURLCompletionBox(completion)

        guard let typeIdentifier = preferredRepresentationTypeIdentifier(for: providerBox.value) else {
            loadFallbackFileURL(from: providerBox, completion: completionBox)
            return
        }

        let originalURLCompletionBox: OptionalURLCompletionBox = OptionalURLCompletionBox { originalURL in
            providerBox.value.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                guard let url else {
                    loadDataRepresentation(
                        from: providerBox,
                        typeIdentifier: typeIdentifier,
                        originalURL: originalURL,
                        completion: completionBox
                    )
                    return
                }

                do {
                    let materializedURL: URL = try materializeImportedFile(
                        at: url,
                        originalURL: originalURL,
                        provider: providerBox.value,
                        typeIdentifier: typeIdentifier
                    )
                    guard fileSize(of: materializedURL) != 0 else {
                        loadDataRepresentation(
                            from: providerBox,
                            typeIdentifier: typeIdentifier,
                            originalURL: originalURL,
                            completion: completionBox
                        )
                        return
                    }
                    completionBox.complete(materializedURL)
                } catch {
                    loadDataRepresentation(
                        from: providerBox,
                        typeIdentifier: typeIdentifier,
                        originalURL: originalURL,
                        completion: completionBox
                    )
                }
            }
        }

        loadFallbackFileURL(from: providerBox, completion: originalURLCompletionBox)
    }

    private static func loadFallbackFileURL(
        from provider: ItemProviderBox,
        completion: OptionalURLCompletionBox
    ) {
        _ = provider.value.loadObject(ofClass: NSURL.self) { object, _ in
            guard let url = object as? URL, url.isFileURL else {
                completion.complete(nil)
                return
            }
            completion.complete(url)
        }
    }

    private static func loadDataRepresentation(
        from provider: ItemProviderBox,
        typeIdentifier: String,
        originalURL: URL?,
        completion: OptionalURLCompletionBox
    ) {
        provider.value.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
            if let data, !data.isEmpty {
                do {
                    let materializedURL: URL = try materializeImportedData(
                        data,
                        originalURL: originalURL,
                        provider: provider.value,
                        typeIdentifier: typeIdentifier
                    )
                    completion.complete(materializedURL)
                    return
                } catch {
                }
            }

            if let originalURL, fileSize(of: originalURL) ?? 0 > 0 {
                completion.complete(originalURL)
                return
            }

            completion.complete(nil)
        }
    }

    private static func preferredRepresentationTypeIdentifier(for provider: NSItemProvider) -> String? {
        provider.registeredTypeIdentifiers.first { typeIdentifier in
            guard typeIdentifier != UTType.fileURL.identifier,
                  typeIdentifier != UTType.url.identifier,
                  let type = UTType(typeIdentifier) else {
                return false
            }
            return isSupportedRepresentationType(type)
        }
    }

    private static func isSupportedRepresentationType(_ type: UTType) -> Bool {
        if type.conforms(to: .audio) || type.conforms(to: .pdf) || type.conforms(to: .image) {
            return true
        }

        guard let fileExtension = type.preferredFilenameExtension?.lowercased() else {
            return false
        }
        return FileType.from(extension: fileExtension) != nil
    }

    private static func materializeImportedFile(
        at sourceURL: URL,
        originalURL: URL?,
        provider: NSItemProvider,
        typeIdentifier: String
    ) throws -> URL {
        let destinationURL: URL = try materializedImportURL(
            for: sourceURL,
            originalURL: originalURL,
            provider: provider,
            typeIdentifier: typeIdentifier
        )
        let fileManager: FileManager = .default

        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: destinationURL.path()) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    private static func materializeImportedData(
        _ data: Data,
        originalURL: URL?,
        provider: NSItemProvider,
        typeIdentifier: String
    ) throws -> URL {
        let destinationURL: URL = try materializedImportURL(
            for: originalURL ?? FileManager.default.temporaryDirectory,
            originalURL: originalURL,
            provider: provider,
            typeIdentifier: typeIdentifier
        )
        let fileManager: FileManager = .default

        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: destinationURL.path()) {
            try fileManager.removeItem(at: destinationURL)
        }
        try data.write(to: destinationURL, options: .atomic)
        return destinationURL
    }

    private static func materializedImportURL(
        for sourceURL: URL,
        originalURL: URL?,
        provider: NSItemProvider,
        typeIdentifier: String
    ) throws -> URL {
        let baseDirectory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent(materializedImportDirectoryName, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileName: String = preferredFileName(
            for: sourceURL,
            originalURL: originalURL,
            provider: provider,
            typeIdentifier: typeIdentifier
        )
        return baseDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    private static func preferredFileName(
        for sourceURL: URL,
        originalURL: URL?,
        provider: NSItemProvider,
        typeIdentifier: String
    ) -> String {
        let preferredExtension: String? = preferredFileExtension(
            for: sourceURL,
            provider: provider,
            typeIdentifier: typeIdentifier
        )

        if let originalURL,
           let originalFileName = sanitizedFileName(originalURL.lastPathComponent),
           !originalFileName.isEmpty {
            return originalFileName
        }

        if let suggestedName = sanitizedFileName(provider.suggestedName), !suggestedName.isEmpty {
            if let preferredExtension, !suggestedName.lowercased().hasSuffix(".\(preferredExtension)") {
                return "\(suggestedName).\(preferredExtension)"
            }
            return suggestedName
        }

        if let sourceFileName = sanitizedFileName(sourceURL.lastPathComponent),
           !sourceFileName.isEmpty {
            return sourceFileName
        }

        if let preferredExtension {
            return "Imported File.\(preferredExtension)"
        }
        return "Imported File"
    }

    private static func preferredFileExtension(
        for sourceURL: URL,
        provider: NSItemProvider,
        typeIdentifier: String
    ) -> String? {
        let sourceExtension: String = sourceURL.pathExtension.lowercased()
        if FileType.from(extension: sourceExtension) != nil {
            return sourceExtension
        }

        if let suggestedName = provider.suggestedName {
            let suggestedExtension: String = (suggestedName as NSString).pathExtension.lowercased()
            if FileType.from(extension: suggestedExtension) != nil {
                return suggestedExtension
            }
        }

        if let typeExtension = UTType(typeIdentifier)?.preferredFilenameExtension?.lowercased(),
           FileType.from(extension: typeExtension) != nil {
            return typeExtension
        }

        return nil
    }

    private static func sanitizedFileName(_ fileName: String?) -> String? {
        guard let fileName else { return nil }
        let trimmed: String = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    private static func fileSize(of url: URL) -> Int? {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path())
        } catch {
            return nil
        }
        if let fileSize = attributes[.size] as? NSNumber {
            return fileSize.intValue
        }
        return attributes[.size] as? Int
    }
}

private final class LockedURLStore: @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private var valuesByIndex: [Int: URL] = [:]

    func append(_ url: URL, at index: Int) {
        lock.lock()
        defer { lock.unlock() }
        valuesByIndex[index] = url
    }

    func snapshot() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return valuesByIndex.keys.sorted().compactMap { valuesByIndex[$0] }
    }
}

private final class ItemProviderBox: @unchecked Sendable {
    let value: NSItemProvider

    init(_ value: NSItemProvider) {
        self.value = value
    }
}

private final class OptionalURLCompletionBox: @unchecked Sendable {
    private let completion: (URL?) -> Void

    init(_ completion: @escaping (URL?) -> Void) {
        self.completion = completion
    }

    func complete(_ url: URL?) {
        completion(url)
    }
}
