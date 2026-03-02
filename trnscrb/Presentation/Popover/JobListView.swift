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
                            JobRowView(job: job)
                            Divider()
                        }
                    } header: {
                        sectionHeader("Active")
                    }
                }

                if !viewModel.completedJobs.isEmpty {
                    Section {
                        ForEach(viewModel.completedJobs) { job in
                            JobRowView(job: job) {
                                viewModel.copyToClipboard(jobID: job.id)
                            }
                            Divider()
                        }
                    } header: {
                        sectionHeader("Recent")
                    }
                }
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
}
