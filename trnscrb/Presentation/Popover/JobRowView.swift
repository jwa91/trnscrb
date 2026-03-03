import SwiftUI

/// A single row in the job list showing file name, type icon, and status.
struct JobRowView: View {
    /// The job to display.
    let job: Job
    /// Whether this row is currently selected for keyboard actions.
    var isSelected: Bool = false
    /// Called when the row becomes selected.
    var onSelect: (() -> Void)?
    /// Called when the user clicks a completed job to copy its markdown.
    var onCopy: (() -> Void)?
    /// Called when the user deletes this job.
    var onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
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
                    .padding(.leading, 24)
                    .help(detailMessage)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect?()
            if case .completed = job.status {
                onCopy?()
            }
        }
        .contextMenu {
            if case .completed = job.status {
                Button("Copy Markdown") {
                    onCopy?()
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
        if job.deliveryWarnings.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                Text("Done")
            }
            .foregroundStyle(.green)
            .font(.caption2)
        } else {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle.fill")
                Text("Done")
            }
            .foregroundStyle(.orange)
            .font(.caption2)
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
}
