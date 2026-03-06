import SwiftUI

/// Displays active and recently completed jobs in the menu panel.
struct JobListView: View {
    /// The job list view model.
    @ObservedObject var viewModel: JobListViewModel
    @State private var isClearAllHovered: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PopoverDesign.sectionSpacing) {
                if !viewModel.activeJobs.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeader("ACTIVE")
                        ForEach(viewModel.activeJobs) { job in
                            row(for: job, allowsCopy: false)
                        }
                    }
                }

                if !viewModel.completedJobs.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            sectionHeader("RECENT")
                            Spacer()
                            Button("Clear All") {
                                viewModel.clearCompleted()
                            }
                            .buttonStyle(.plain)
                            .font(PopoverDesign.secondaryTextFont)
                            .foregroundStyle(
                                isClearAllHovered ? Color.accentColor : Color.secondary
                            )
                            .underline(isClearAllHovered)
                            .pointingHandCursor()
                            .onHover { isClearAllHovered = $0 }
                        }

                        ForEach(viewModel.completedJobs) { job in
                            row(for: job, allowsCopy: true)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: viewModel.jobs) { _, jobs in
            if let selectedJobID = viewModel.selectedJobID,
               !jobs.contains(where: { $0.id == selectedJobID }) {
                viewModel.selectJob(id: nil)
            }
        }
    }

    @ViewBuilder
    private func row(for job: Job, allowsCopy: Bool) -> some View {
        let copyFeedback: JobListViewModel.CopyFeedback? = viewModel.copyFeedback
        let showsMarkdownCopyConfirmation: Bool = copyFeedback?.jobID == job.id
            && copyFeedback?.target == .markdown
        let showsSourceCopyConfirmation: Bool = copyFeedback?.jobID == job.id
            && copyFeedback?.target == .sourceURL
        JobRowView(
            job: job,
            isSelected: viewModel.selectedJobID == job.id,
            showsMarkdownCopyConfirmation: showsMarkdownCopyConfirmation,
            showsSourceCopyConfirmation: showsSourceCopyConfirmation,
            onSelect: { viewModel.selectJob(id: job.id) },
            onCopyMarkdown: allowsCopy ? { viewModel.copyToClipboard(jobID: job.id) } : nil,
            onCopySourceURL: allowsCopy && job.presignedSourceURL != nil
                ? { viewModel.copySourceURLToClipboard(jobID: job.id) }
                : nil,
            onDelete: { viewModel.removeJob(id: job.id) }
        )
        .id(rowID(for: job))
    }

    private func rowID(for job: Job) -> String {
        "\(job.id.uuidString)-\(statusToken(for: job.status))"
    }

    private func statusToken(for status: JobStatus) -> String {
        switch status {
        case .pending:
            return "pending"
        case .uploading:
            return "uploading"
        case .processing:
            return "processing"
        case .completed:
            return "completed"
        case .failed:
            return "failed"
        }
    }

    /// Section header label.
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(PopoverDesign.sectionLabelFont)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}
