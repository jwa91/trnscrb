import SwiftUI

/// Displays active and recently completed jobs in the popover.
struct JobListView: View {
    /// The job list view model.
    @ObservedObject var viewModel: JobListViewModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !viewModel.activeJobs.isEmpty {
                    Section {
                        ForEach(viewModel.activeJobs) { job in
                            JobRowView(
                                job: job,
                                isSelected: viewModel.selectedJobID == job.id,
                                onSelect: { viewModel.selectJob(id: job.id) },
                                onDelete: { viewModel.removeJob(id: job.id) }
                            )
                            Divider()
                        }
                    } header: {
                        sectionHeader("Active")
                    }
                }

                if !viewModel.completedJobs.isEmpty {
                    Section {
                        ForEach(viewModel.completedJobs) { job in
                            JobRowView(
                                job: job,
                                isSelected: viewModel.selectedJobID == job.id,
                                onSelect: { viewModel.selectJob(id: job.id) },
                                onCopy: { viewModel.copyToClipboard(jobID: job.id) },
                                onDelete: { viewModel.removeJob(id: job.id) }
                            )
                            Divider()
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
                            .buttonStyle(.borderless)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                    }
                }
            }
        }
        .onDeleteCommand(perform: handleDeleteCommand)
        .onChange(of: viewModel.jobs) { _, jobs in
            if let selectedJobID = viewModel.selectedJobID,
               !jobs.contains(where: { $0.id == selectedJobID }) {
                viewModel.selectJob(id: nil)
            }
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
