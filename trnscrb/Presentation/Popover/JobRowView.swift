import SwiftUI

/// A single row in the job list showing file name, type icon, and status.
struct JobRowView: View {
    /// The job to display.
    let job: Job
    /// Whether this row is currently selected for keyboard actions.
    var isSelected: Bool = false
    /// Whether the inline markdown preview is visible.
    var isExpanded: Bool = false
    /// Whether markdown copy confirmation is visible.
    var showsMarkdownCopyConfirmation: Bool = false
    /// Whether source URL copy confirmation is visible.
    var showsSourceCopyConfirmation: Bool = false
    /// Called when the row becomes selected.
    var onSelect: (() -> Void)?
    /// Called when the user requests a markdown copy.
    var onCopyMarkdown: (() -> Void)?
    /// Called when the user requests copying the source URL.
    var onCopySourceURL: (() -> Void)?
    /// Called when the user toggles preview expansion.
    var onToggleExpansion: (() -> Void)?
    /// Called when the user deletes this job.
    var onDelete: (() -> Void)?
    @State private var isHovered: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                leadingIndicatorView
                Image(systemName: fileTypeIcon)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(job.fileName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.caption)
                Spacer()
                statusView
            }

            if let detailMessage = detailMessage {
                Text(detailMessage)
                    .font(.caption2)
                    .foregroundStyle(detailColor)
                    .lineLimit(2)
                    .padding(.leading, leadingContentPadding)
                    .help(detailMessage)
            }

            if isExpanded, let markdownPreview {
                VStack(alignment: .leading, spacing: 6) {
                    Text(markdownPreview)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(4)
                        .allowsHitTesting(false)
                        .foregroundStyle(.primary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )
                }
                .padding(.leading, leadingContentPadding)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(rowBackgroundColor)
        .contentShape(Rectangle())
        .pointingHandCursor()
        .onHover { isHovered = $0 }
        .onTapGesture {
            handleRowTap()
        }
        .contextMenu {
            if case .completed = job.status {
                Button("Copy Markdown") {
                    onCopyMarkdown?()
                }
                if onCopySourceURL != nil {
                    Button("Copy S3 URL") {
                        onCopySourceURL?()
                    }
                }
            }
            Button("Delete", role: .destructive) {
                onDelete?()
            }
        }
    }

    /// SF Symbol name for the file type.
    private var fileTypeIcon: String {
        switch job.fileType {
        case .audio: return "waveform"
        case .pdf: return "doc.richtext"
        case .image: return "photo"
        }
    }

    /// Status indicator view.
    @ViewBuilder
    private var statusView: some View {
        switch job.status {
        case .pending:
            Text("Waiting")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .uploading(let progress):
            ProgressView(value: progress)
                .frame(width: 40)
        case .processing:
            ProgressView()
                .controlSize(.small)
        case .completed:
            completionStatusView
        case .failed:
            HStack(spacing: 4) {
                Image(systemName: "exclamation.triangle.fill")
                Text("Failed")
            }
            .foregroundStyle(.red)
            .font(.caption2)
        }
    }

    @ViewBuilder
    private var completionStatusView: some View {
        HStack(spacing: 6) {
            if let onCopyMarkdown {
                completionActionButton(
                    systemName: "doc.on.doc",
                    title: "Copy Markdown",
                    successTitle: "Copied Markdown",
                    isConfirmed: showsMarkdownCopyConfirmation,
                    action: onCopyMarkdown
                )
            }

            if let onCopySourceURL {
                completionActionButton(
                    systemName: "link",
                    title: "Copy S3 URL",
                    successTitle: "Copied S3 URL",
                    isConfirmed: showsSourceCopyConfirmation,
                    action: onCopySourceURL
                )
            }

        }
        .animation(.easeOut(duration: 0.18), value: showsMarkdownCopyConfirmation)
        .animation(.easeOut(duration: 0.18), value: showsSourceCopyConfirmation)
    }

    @ViewBuilder
    private var leadingIndicatorView: some View {
        if case .completed = job.status {
            completionTimestampView
                .frame(width: leadingIndicatorWidth, alignment: .leading)
        } else {
            Color.clear
                .frame(width: leadingIndicatorWidth, height: 1)
        }
    }

    private var detailMessage: String? {
        if case .failed(let error) = job.status {
            return error
        }
        return job.warningMessage
    }

    private var detailColor: Color {
        if case .failed = job.status {
            return .red
        }
        return .orange
    }

    private var rowBackgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.12)
        }
        if isHovered {
            return Color.primary.opacity(0.04)
        }
        return .clear
    }

    private var leadingIndicatorWidth: CGFloat {
        36
    }

    private var leadingContentPadding: CGFloat {
        leadingIndicatorWidth + 32
    }

    private var canExpand: Bool {
        if case .completed = job.status {
            return markdownPreview != nil
        }
        return false
    }

    private var markdownPreview: String? {
        guard let markdown = job.markdown?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !markdown.isEmpty else {
            return nil
        }

        let lines: [Substring] = markdown.split(
            separator: "\n",
            maxSplits: 3,
            omittingEmptySubsequences: false
        )
        let preview: String = lines.prefix(4).joined(separator: "\n")
        return preview
    }

    @ViewBuilder
    private var completionTimestampView: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            let display: CompletionTimestampDisplay = completionTimestampDisplay(at: context.date)
            Text(display.text)
                .font(.caption2)
                .foregroundStyle(display.color)
                .monospacedDigit()
                .help(display.tooltip)
        }
    }

    private func completionActionButton(
        systemName: String,
        title: String,
        successTitle: String,
        isEnabled: Bool = true,
        isConfirmed: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            onSelect?()
            action()
        }) {
            Image(systemName: isConfirmed ? "checkmark" : systemName)
                .font(.caption2.weight(.semibold))
                .frame(width: 12, height: 12)
                .foregroundStyle(isConfirmed ? Color.green : Color.primary)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.mini)
        .labelStyle(.iconOnly)
        .help(isConfirmed ? successTitle : title)
        .disabled(!isEnabled)
        .pointingHandCursor()
    }

    private func handleRowTap() {
        onSelect?()
        if canExpand {
            onToggleExpansion?()
        }
    }

    private func completionTimestampDisplay(at now: Date) -> CompletionTimestampDisplay {
        let baseColor: Color = job.deliveryWarnings.isEmpty ? .secondary : .orange
        guard let completedAt: Date = job.completedAt else {
            return CompletionTimestampDisplay(
                text: "done",
                tooltip: "Completed",
                color: baseColor
            )
        }

        let elapsed: TimeInterval = max(0, now.timeIntervalSince(completedAt))
        let text: String
        let color: Color
        if elapsed < 30 {
            text = "now"
            color = .green
        } else {
            text = Self.completionTimestampFormatter.string(from: completedAt)
            color = baseColor
        }

        return CompletionTimestampDisplay(
            text: text,
            tooltip: "Completed \(Self.completionTooltipFormatter.string(from: completedAt))",
            color: color
        )
    }

    private struct CompletionTimestampDisplay {
        let text: String
        let tooltip: String
        let color: Color
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
