import SwiftUI

/// A single row in the job list showing file name, type icon, and status.
struct JobRowView: View {
    /// The job to display.
    let job: Job
    /// Whether this row is currently selected for keyboard actions.
    var isSelected: Bool = false
    /// Whether markdown copy confirmation is visible.
    var showsMarkdownCopyConfirmation: Bool = false
    /// Whether source URL copy confirmation is visible.
    var showsSourceCopyConfirmation: Bool = false
    /// Called when the row becomes selected.
    var onSelect: (() -> Void)?
    /// Called when the row should perform its primary action.
    var onPrimaryAction: (() -> Void)?
    /// Called when the user requests a markdown copy.
    var onCopyMarkdown: (() -> Void)?
    /// Called when the user requests copying the source URL.
    var onCopySourceURL: (() -> Void)?
    /// Called when the user deletes this job.
    var onDelete: (() -> Void)?

    @State private var isHovered: Bool = false

    var body: some View {
        let presentation: JobRowPresentation = JobRowPresentation(job: job)

        return HStack(alignment: .top, spacing: 10) {
            selectionButton(for: presentation)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailingActions(for: presentation)
        }
        .padding(.vertical, PopoverDesign.rowVerticalPadding)
        .padding(.horizontal, PopoverDesign.rowHorizontalPadding)
        .frame(maxWidth: .infinity, minHeight: PopoverDesign.rowMinHeight, alignment: .leading)
        .background(
            RoundedRectangle(
                cornerRadius: PopoverDesign.rowCornerRadius,
                style: .continuous
            )
            .fill(rowBackgroundColor)
        )
        .contentShape(
            RoundedRectangle(
                cornerRadius: PopoverDesign.rowCornerRadius,
                style: .continuous
            )
        )
        .onHover { isHovered = $0 }
        .contextMenu {
            if case .completed = job.status {
                Button("Copy Markdown") {
                    onCopyMarkdown?()
                }
                if onCopySourceURL != nil {
                    Button("Copy Source URL") {
                        onCopySourceURL?()
                    }
                }
            }
            Button("Delete", role: .destructive) {
                onDelete?()
            }
        }
    }

    private func selectionButton(for presentation: JobRowPresentation) -> some View {
        Button {
            onSelect?()
            onPrimaryAction?()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                fileTypeBadge(presentation)

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(presentation.titleText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .font(PopoverDesign.primaryRowFont)

                        subtitleView(for: presentation)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 8)

                    statusView(for: presentation)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(
                RoundedRectangle(
                    cornerRadius: PopoverDesign.rowCornerRadius,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func subtitleView(for presentation: JobRowPresentation) -> some View {
        if case .completed = job.status, presentation.subtitleKind == .metadata {
            TimelineView(.periodic(from: .now, by: 5)) { context in
                let updated: JobRowPresentation = JobRowPresentation(job: job, now: context.date)
                subtitleText(
                    updated.subtitleText,
                    kind: updated.subtitleKind,
                    tooltip: updated.subtitleTooltip
                )
            }
        } else {
            subtitleText(
                presentation.subtitleText,
                kind: presentation.subtitleKind,
                tooltip: presentation.subtitleTooltip
            )
        }
    }

    @ViewBuilder
    private func statusView(for presentation: JobRowPresentation) -> some View {
        switch job.status {
        case .pending:
            statusPill("Waiting")
        case .uploading:
            if let uploadActivity = presentation.uploadActivity {
                uploadActivityView(uploadActivity)
            }
        case .processing:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Processing")
                    .font(PopoverDesign.secondaryTextFont)
                    .foregroundStyle(.secondary)
            }
        case .failed:
            statusPill(
                "Failed",
                color: .red,
                systemImage: "exclamationmark.triangle.fill"
            )
        case .completed:
            EmptyView()
        }
    }

    @ViewBuilder
    private func trailingActions(for presentation: JobRowPresentation) -> some View {
        switch job.status {
        case .completed:
            completionTrailingView(for: presentation)
        case .pending, .uploading, .processing, .failed:
            if let onDelete {
                deleteActionButton(action: onDelete)
            }
        }
    }

    @ViewBuilder
    private func uploadActivityView(_ activity: JobRowPresentation.UploadActivity) -> some View {
        switch activity {
        case .progress(let percent, let value):
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(percent)%")
                    .font(PopoverDesign.secondaryTextFont)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                ProgressView(value: value)
                    .frame(width: 56)
            }
        case .finalizing:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Finalizing")
                    .font(PopoverDesign.secondaryTextFont)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func completionTrailingView(for presentation: JobRowPresentation) -> some View {
        HStack(spacing: PopoverDesign.actionButtonSpacing) {
            if presentation.showsMarkdownAction, let onCopyMarkdown {
                rowActionButton(
                    systemName: "doc.on.doc",
                    title: "Copy Markdown",
                    successTitle: "Copied Markdown",
                    isConfirmed: showsMarkdownCopyConfirmation,
                    action: onCopyMarkdown
                )
            }

            if presentation.showsSourceLinkAction, let onCopySourceURL {
                rowActionButton(
                    systemName: "link",
                    title: "Copy Source URL",
                    successTitle: "Copied Source URL",
                    isConfirmed: showsSourceCopyConfirmation,
                    action: onCopySourceURL
                )
            }

            if let onDelete {
                deleteActionButton(action: onDelete)
            }
        }
        .frame(width: PopoverDesign.completionActionsWidth, alignment: .trailing)
        .animation(.easeOut(duration: 0.18), value: showsMarkdownCopyConfirmation)
        .animation(.easeOut(duration: 0.18), value: showsSourceCopyConfirmation)
    }

    private func fileTypeBadge(_ presentation: JobRowPresentation) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(badgeColor(for: presentation.badgeTint).opacity(0.16))

            Image(systemName: presentation.badgeSymbolName)
                .font(.system(size: PopoverDesign.rowBadgeSymbolSize, weight: .semibold))
                .foregroundStyle(badgeColor(for: presentation.badgeTint))
        }
        .frame(width: PopoverDesign.rowBadgeSize, height: PopoverDesign.rowBadgeSize)
    }

    private func subtitleText(
        _ text: String,
        kind: JobRowPresentation.SubtitleKind,
        tooltip: String?
    ) -> some View {
        Text(text)
            .font(PopoverDesign.secondaryTextFont)
            .foregroundStyle(subtitleColor(for: kind))
            .lineLimit(kind == .metadata ? 1 : 2)
            .help(tooltip ?? text)
    }

    private func statusPill(
        _ title: String,
        color: Color = .secondary,
        systemImage: String? = nil
    ) -> some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
            }

            Text(title)
                .font(PopoverDesign.secondaryTextFont)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(color.opacity(0.1))
        )
    }

    private var rowBackgroundColor: Color {
        if isSelected {
            return PopoverDesign.rowSelectedBackground
        }
        if isHovered {
            return PopoverDesign.rowHoverBackground
        }
        return .clear
    }

    private func badgeColor(for tint: JobRowPresentation.BadgeTint) -> Color {
        switch tint {
        case .orange:
            return .orange
        case .red:
            return .red
        case .blue:
            return .blue
        }
    }

    private func subtitleColor(for kind: JobRowPresentation.SubtitleKind) -> Color {
        switch kind {
        case .metadata:
            return .secondary
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    private func rowActionButton(
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
                .font(.system(size: PopoverDesign.actionButtonSymbolSize, weight: .semibold))
                .frame(
                    width: PopoverDesign.actionButtonSize,
                    height: PopoverDesign.actionButtonSize
                )
                .foregroundStyle(isConfirmed ? Color.green : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isConfirmed ? Color.green.opacity(0.12) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .labelStyle(.iconOnly)
        .help(isConfirmed ? successTitle : title)
        .disabled(!isEnabled)
        .pointingHandCursor()
    }

    private func deleteActionButton(action: @escaping () -> Void) -> some View {
        Button(action: {
            onSelect?()
            action()
        }) {
            Image(systemName: "trash")
                .font(.system(size: PopoverDesign.actionButtonSymbolSize, weight: .semibold))
                .frame(
                    width: PopoverDesign.actionButtonSize,
                    height: PopoverDesign.actionButtonSize
                )
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .labelStyle(.iconOnly)
        .help("Delete")
        .pointingHandCursor()
    }
}
