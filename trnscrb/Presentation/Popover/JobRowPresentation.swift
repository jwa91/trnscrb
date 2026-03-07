import Foundation

struct JobRowPresentation {
    enum BadgeTint: Equatable {
        case orange
        case red
        case blue
    }

    enum MirroringActivity: Equatable {
        case progress(percent: Int, value: Double)
        case finalizing
    }

    enum SubtitleKind: Equatable {
        case metadata
        case warning
        case error
    }

    let badgeSymbolName: String
    let badgeTint: BadgeTint
    let titleText: String
    let subtitleText: String
    let subtitleKind: SubtitleKind
    let subtitleTooltip: String?
    let mirroringActivity: MirroringActivity?
    let showsCompletionActions: Bool
    let showsPassiveCompletionState: Bool
    let showsMarkdownAction: Bool
    let showsSourceLinkAction: Bool

    init(job: Job, now: Date = Date()) {
        badgeSymbolName = Self.badgeSymbolName(for: job.fileType)
        badgeTint = Self.badgeTint(for: job.fileType)
        titleText = job.fileName

        let subtitle: Subtitle = Self.subtitle(for: job, now: now)
        subtitleText = subtitle.text
        subtitleKind = subtitle.kind
        subtitleTooltip = subtitle.tooltip
        mirroringActivity = Self.mirroringActivity(for: job.status)

        if case .completed = job.status {
            showsMarkdownAction = true
            showsSourceLinkAction = job.presignedSourceURL != nil
        } else {
            showsMarkdownAction = false
            showsSourceLinkAction = false
        }
        showsCompletionActions = showsMarkdownAction || showsSourceLinkAction
        showsPassiveCompletionState = false
    }

    private struct Subtitle {
        let text: String
        let kind: SubtitleKind
        let tooltip: String?
    }

    static func typeLabel(for fileType: FileType) -> String {
        switch fileType {
        case .audio:
            return "Audio"
        case .pdf:
            return "PDF"
        case .image:
            return "Image"
        }
    }

    private static func badgeSymbolName(for fileType: FileType) -> String {
        switch fileType {
        case .audio:
            return "waveform"
        case .pdf:
            return "doc.richtext"
        case .image:
            return "photo"
        }
    }

    private static func badgeTint(for fileType: FileType) -> BadgeTint {
        switch fileType {
        case .audio:
            return .orange
        case .pdf:
            return .red
        case .image:
            return .blue
        }
    }

    private static func subtitle(for job: Job, now: Date) -> Subtitle {
        let typeLabel: String = typeLabel(for: job.fileType)

        if case .failed(let error) = job.status {
            return Subtitle(
                text: error,
                kind: .error,
                tooltip: error
            )
        }

        if let warningMessage: String = job.warningMessage {
            return Subtitle(
                text: warningMessage,
                kind: .warning,
                tooltip: warningMessage
            )
        }

        switch job.status {
        case .pending:
            return Subtitle(
                text: "\(typeLabel) • Waiting",
                kind: .metadata,
                tooltip: "Waiting"
            )
        case .mirroring(let progress):
            if isFinalizingMirroring(progress) {
                return Subtitle(
                    text: "\(typeLabel) • Finalizing mirroring",
                    kind: .metadata,
                    tooltip: "Finalizing mirroring"
                )
            }

            let percent: Int = mirroringPercent(for: progress)
            return Subtitle(
                text: "\(typeLabel) • Mirroring \(percent)%",
                kind: .metadata,
                tooltip: "Mirroring"
            )
        case .processing:
            return Subtitle(
                text: "\(typeLabel) • Processing",
                kind: .metadata,
                tooltip: "Processing"
            )
        case .delivering:
            return Subtitle(
                text: "\(typeLabel) • Delivering",
                kind: .metadata,
                tooltip: "Delivering"
            )
        case .completed:
            guard let completedAt: Date = job.completedAt else {
                return Subtitle(
                    text: "\(typeLabel) • Completed",
                    kind: .metadata,
                    tooltip: "Completed"
                )
            }

            let elapsed: TimeInterval = max(0, now.timeIntervalSince(completedAt))
            let timeText: String
            if elapsed < 30 {
                timeText = "now"
            } else {
                timeText = completionTimestampFormatter.string(from: completedAt)
            }

            return Subtitle(
                text: "\(typeLabel) • \(timeText)",
                kind: .metadata,
                tooltip: "Completed \(completionTooltipFormatter.string(from: completedAt))"
            )
        case .failed(let error):
            return Subtitle(
                text: error,
                kind: .error,
                tooltip: error
            )
        }
    }

    private static func mirroringActivity(for status: JobStatus) -> MirroringActivity? {
        guard case .mirroring(let progress) = status else { return nil }
        if isFinalizingMirroring(progress) {
            return .finalizing
        }
        return .progress(percent: mirroringPercent(for: progress), value: progress)
    }

    private static func isFinalizingMirroring(_ progress: Double) -> Bool {
        min(max(progress, 0), 1) >= 1
    }

    private static func mirroringPercent(for progress: Double) -> Int {
        min(Int((min(max(progress, 0), 1) * 100).rounded()), 99)
    }

    private static let completionTimestampFormatter: DateFormatter = {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("Hm")
        return formatter
    }()

    private static let completionTooltipFormatter: DateFormatter = {
        let formatter: DateFormatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
