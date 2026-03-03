import SwiftUI

/// A single row in the job list showing file name, type icon, and status.
struct JobRowView: View {
    /// The job to display.
    let job: Job
    /// Whether this row is currently selected for keyboard actions.
    var isSelected: Bool = false
    /// Whether the inline markdown preview is visible.
    var isExpanded: Bool = false
    /// Whether the copied confirmation is visible.
    var showsCopyConfirmation: Bool = false
    /// Called when the row becomes selected.
    var onSelect: (() -> Void)?
    /// Called when the user requests a markdown copy.
    var onCopy: (() -> Void)?
    /// Called when the user wants to reveal the saved markdown file in Finder.
    var onRevealInFinder: (() -> Void)?
    /// Called when the user toggles preview expansion.
    var onToggleExpansion: (() -> Void)?
    /// Called when the user deletes this job.
    var onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if canExpand {
                    Button(action: { onToggleExpansion?() }) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 10)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear
                        .frame(width: 10, height: 10)
                }
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
                    .padding(.leading, 34)
                    .help(detailMessage)
            }

            if isExpanded, let markdownPreview {
                VStack(alignment: .leading, spacing: 6) {
                    Text(markdownPreview)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(4)
                        .textSelection(.enabled)
                        .foregroundStyle(.primary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )

                    if let savedFileURL = job.savedFileURL {
                        Link(destination: savedFileURL) {
                            Label {
                                Text(savedFileURL.path())
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            } icon: {
                                Image(systemName: "doc.text")
                            }
                            .font(.caption2)
                        }
                        .help(savedFileURL.path())
                    }

                    if let presignedSourceURL = job.presignedSourceURL {
                        Link(destination: presignedSourceURL) {
                            Label("Open S3 URL", systemImage: "link")
                                .font(.caption2)
                        }
                        .help(presignedSourceURL.absoluteString)
                    }
                }
                .padding(.leading, 34)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .contextMenu {
            if case .completed = job.status {
                Button("Copy Markdown") {
                    onCopy?()
                }
                if onRevealInFinder != nil {
                    Button("Reveal in Finder") {
                        onRevealInFinder?()
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
            completionIndicator

            if let onCopy {
                completionActionButton(
                    systemName: "doc.on.doc",
                    title: "Copy Markdown",
                    action: onCopy
                )
            }

            completionActionButton(
                systemName: "folder",
                title: "Reveal in Finder",
                action: { onRevealInFinder?() }
            )

            if showsCopyConfirmation {
                Text("Copied!")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: showsCopyConfirmation)
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
    private var completionIndicator: some View {
        if job.deliveryWarnings.isEmpty {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption2)
        } else {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
                .font(.caption2)
        }
    }

    private func completionActionButton(
        systemName: String,
        title: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption2.weight(.semibold))
                .frame(width: 12, height: 12)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.mini)
        .labelStyle(.iconOnly)
        .help(title)
        .disabled(!isEnabled)
    }
}
