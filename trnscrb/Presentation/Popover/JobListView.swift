import SwiftUI

/// Displays active and recently completed jobs in the popover.
struct JobListView: View {
    /// The job list view model.
    @ObservedObject var viewModel: JobListViewModel
    @State private var expandedJobIDs: Set<UUID> = []
    @State private var isClearAllHovered: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if !viewModel.activeJobs.isEmpty {
                    Section {
                        ForEach(viewModel.activeJobs) { job in
                            row(for: job, allowsCopy: false)
                        }
                    } header: {
                        sectionHeader("Active")
                    }
                }

                if !viewModel.completedJobs.isEmpty {
                    Section {
                        ForEach(viewModel.completedJobs) { job in
                            row(for: job, allowsCopy: true)
                        }
                    } header: {
                        HStack {
                            Text("Recent")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            Spacer()
                            Button("Clear All") {
                                viewModel.clearCompleted()
                            }
                            .buttonStyle(.plain)
                            .font(.caption2)
                            .foregroundStyle(
                                isClearAllHovered ? Color.accentColor : Color.secondary
                            )
                            .underline(isClearAllHovered)
                            .pointingHandCursor()
                            .onHover { isClearAllHovered = $0 }
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onDeleteCommand(perform: handleDeleteCommand)
        .onChange(of: viewModel.jobs) { _, jobs in
            let currentIDs: Set<UUID> = Set(jobs.map(\.id))
            expandedJobIDs = expandedJobIDs.intersection(currentIDs)
            if let selectedJobID = viewModel.selectedJobID,
               !jobs.contains(where: { $0.id == selectedJobID }) {
                viewModel.selectJob(id: nil)
            }
        }
    }

    @ViewBuilder
    private func row(for job: Job, allowsCopy: Bool) -> some View {
        let isCompleted: Bool = {
            if case .completed = job.status {
                return true
            }
            return false
        }()
        JobRowView(
            job: job,
            isSelected: viewModel.selectedJobID == job.id,
            isExpanded: expandedJobIDs.contains(job.id),
            showsCopyConfirmation: viewModel.copiedJobID == job.id,
            onSelect: { viewModel.selectJob(id: job.id) },
            onCopy: allowsCopy ? { viewModel.copyToClipboard(jobID: job.id) } : nil,
            onRevealInFinder: allowsCopy ? { viewModel.revealInFinder(jobID: job.id) } : nil,
            onToggleExpansion: isCompleted ? { toggleExpansion(for: job.id) } : nil,
            onDelete: { viewModel.removeJob(id: job.id) }
        )
        .id(rowID(for: job))
        Divider()
    }

    private func toggleExpansion(for jobID: UUID) {
        if expandedJobIDs.contains(jobID) {
            expandedJobIDs.remove(jobID)
        } else {
            expandedJobIDs.insert(jobID)
        }
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
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func handleDeleteCommand() {
        if let selectedJobID = viewModel.selectedJobID {
            viewModel.removeJob(id: selectedJobID)
            viewModel.selectJob(id: nil)
            return
        }
        if let fallbackID: UUID = viewModel.completedJobs.first?.id ?? viewModel.activeJobs.first?.id {
            viewModel.removeJob(id: fallbackID)
        }
    }
}
