import Foundation

/// Builds saved markdown filenames from user-configurable settings.
enum OutputFileNameFormatter {
    static func fileName(
        sourceFileName: String,
        fileType: FileType,
        settings: AppSettings,
        date: Date = Date()
    ) -> String {
        let timestamp: String = timestampString(from: date)
        let originalFilename: String = (sourceFileName as NSString).deletingPathExtension
        let template: String = normalizedTemplate(from: settings.outputFileNameTemplate)

        var resolved: String = template
        resolved = resolved.replacingOccurrences(of: "{originalFilename}", with: originalFilename)
        resolved = resolved.replacingOccurrences(of: "{fileType}", with: fileType.fileNameToken)
        resolved = resolved.replacingOccurrences(of: "{timestamp}", with: timestamp)
        resolved = resolved.replacingOccurrences(of: "{date}", with: dateString(from: date))
        resolved = resolved.replacingOccurrences(of: "{time}", with: timeString(from: date))
        resolved = resolved.replacingOccurrences(
            of: "{prefix}",
            with: settings.outputFileNamePrefix.trimmedCredentialValue
        )

        let sanitized: String = sanitizeBaseName(resolved)
        let baseName: String = sanitized.isEmpty
            ? sanitizeBaseName("\(fileType.fileNameToken)-\(timestamp)")
            : sanitized
        return "\(baseName).md"
    }

    private static func normalizedTemplate(from template: String) -> String {
        let trimmed: String = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return AppSettings.defaultFileNameTemplate
        }
        return trimmed
    }

    private static func sanitizeBaseName(_ value: String) -> String {
        let withoutExtension: String
        if value.lowercased().hasSuffix(".md") {
            withoutExtension = String(value.dropLast(3))
        } else {
            withoutExtension = value
        }

        let disallowedCharacters: CharacterSet = CharacterSet(
            charactersIn: "/:\\?%*|\"<>"
        ).union(.newlines)

        let collapsed: String = withoutExtension.unicodeScalars.map { scalar in
            if disallowedCharacters.contains(scalar) {
                return "-"
            }
            return String(scalar)
        }.joined()

        return collapsed
            .trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines))
    }

    private static func timestampString(from date: Date) -> String {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private static func dateString(from date: Date) -> String {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    private static func timeString(from date: Date) -> String {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "HHmmss"
        return formatter.string(from: date)
    }
}
