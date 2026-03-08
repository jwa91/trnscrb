import Foundation

/// File-backed multipart/form-data body used to avoid buffering large uploads in memory.
struct FileBackedMultipartBody {
    let fileURL: URL
    let contentLength: UInt64

    func makeInputStream() throws -> InputStream {
        guard let stream: InputStream = InputStream(url: fileURL) else {
            throw MistralError.invalidResponse("Could not open the multipart upload body.")
        }
        return stream
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

enum FileBackedMultipartBodyBuilder {
    private static let chunkSize: Int = 64 * 1024

    static func create(
        boundary: String,
        fields: [(name: String, value: String)],
        fileFieldName: String,
        fileURL: URL,
        fileName: String,
        mimeType: String,
        fileAccess: any SecurityScopedFileAccessing,
        filePreparationErrorMessage: String
    ) throws -> FileBackedMultipartBody {
        let bodyFileURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("trnscrb-multipart-\(UUID().uuidString)", isDirectory: false)

        guard FileManager.default.createFile(atPath: bodyFileURL.path(), contents: nil) else {
            throw MistralError.invalidResponse(filePreparationErrorMessage)
        }

        do {
            let outputHandle: FileHandle = try FileHandle(forWritingTo: bodyFileURL)
            do {
                for field in fields {
                    try write("--\(boundary)\r\n", to: outputHandle)
                    try write(
                        "Content-Disposition: form-data; name=\"\(field.name)\"\r\n\r\n",
                        to: outputHandle
                    )
                    try write("\(field.value)\r\n", to: outputHandle)
                }

                try write("--\(boundary)\r\n", to: outputHandle)
                try write(
                    "Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(fileName)\"\r\n",
                    to: outputHandle
                )
                try write("Content-Type: \(mimeType)\r\n\r\n", to: outputHandle)
                try appendFileContents(
                    from: fileURL,
                    to: outputHandle,
                    fileAccess: fileAccess
                )
                try write("\r\n", to: outputHandle)
                try write("--\(boundary)--\r\n", to: outputHandle)
                try outputHandle.close()
            } catch {
                try? outputHandle.close()
                throw error
            }

            let attributes: [FileAttributeKey: Any] = try FileManager.default.attributesOfItem(
                atPath: bodyFileURL.path()
            )
            guard let fileSize: NSNumber = attributes[.size] as? NSNumber else {
                throw MistralError.invalidResponse(filePreparationErrorMessage)
            }
            return FileBackedMultipartBody(
                fileURL: bodyFileURL,
                contentLength: fileSize.uint64Value
            )
        } catch {
            try? FileManager.default.removeItem(at: bodyFileURL)
            if let mistralError: MistralError = error as? MistralError {
                throw mistralError
            }
            throw MistralError.invalidResponse(filePreparationErrorMessage)
        }
    }

    private static func appendFileContents(
        from fileURL: URL,
        to outputHandle: FileHandle,
        fileAccess: any SecurityScopedFileAccessing
    ) throws {
        let startedAccessing: Bool = fileAccess.startAccessing(fileURL)
        defer {
            if startedAccessing {
                fileAccess.stopAccessing(fileURL)
            }
        }

        let inputHandle: FileHandle = try FileHandle(forReadingFrom: fileURL)
        do {
            while true {
                let chunk: Data = try inputHandle.read(upToCount: chunkSize) ?? Data()
                guard !chunk.isEmpty else { break }
                try outputHandle.write(contentsOf: chunk)
            }
            try inputHandle.close()
        } catch {
            try? inputHandle.close()
            throw error
        }
    }

    private static func write(_ string: String, to outputHandle: FileHandle) throws {
        try outputHandle.write(contentsOf: Data(string.utf8))
    }
}
