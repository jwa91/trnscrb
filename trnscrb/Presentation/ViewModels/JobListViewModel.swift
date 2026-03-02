import AppKit
import Foundation

/// Manages the job queue and coordinates file processing.
///
/// Accepts file URLs from drag-and-drop, validates file types, creates `Job`
/// instances, and drives `ProcessFileUseCase` while updating job state. Tracks
/// recent completed jobs (max 10) and provides copy-to-clipboard for results.
@MainActor
public final class JobListViewModel: ObservableObject {
    /// All jobs, both active and completed.
    @Published public var jobs: [Job] = []
    /// Error message when S3 or API key is not configured.
    @Published public var configurationError: String?

    /// Maximum number of completed jobs to retain.
    private let maxCompletedJobs: Int = 10
    /// Pipeline orchestrator.
    private let useCase: ProcessFileUseCase
    /// Settings gateway for configuration checks.
    private let settingsGateway: any SettingsGateway

    /// Creates a job list view model.
    /// - Parameters:
    ///   - useCase: Pipeline orchestrator for processing files.
    ///   - settingsGateway: Settings gateway for pre-flight configuration checks.
    public init(useCase: ProcessFileUseCase, settingsGateway: any SettingsGateway) {
        self.useCase = useCase
        self.settingsGateway = settingsGateway
    }

    /// Jobs that are still active (pending, uploading, or processing).
    public var activeJobs: [Job] {
        jobs.filter { job in
            switch job.status {
            case .pending, .uploading, .processing:
                return true
            case .completed, .failed:
                return false
            }
        }
    }

    /// Jobs that have completed or failed, newest first.
    public var completedJobs: [Job] {
        jobs.filter { job in
            switch job.status {
            case .completed, .failed:
                return true
            case .pending, .uploading, .processing:
                return false
            }
        }
    }

    /// Validates and queues files for processing.
    ///
    /// Unsupported file types are silently filtered. If S3 or API key is not
    /// configured, sets `configurationError` and removes the queued jobs.
    /// - Parameter urls: Local file URLs from drag-and-drop or file picker.
    public func processFiles(_ urls: [URL]) {
        let validURLs: [(URL, FileType)] = urls.compactMap { url in
            let ext: String = url.pathExtension.lowercased()
            guard let fileType: FileType = FileType.from(extension: ext) else { return nil }
            return (url, fileType)
        }
        guard !validURLs.isEmpty else { return }

        // Create jobs synchronously so callers can inspect them immediately.
        var jobIDs: [UUID] = []
        for (url, fileType) in validURLs {
            let job: Job = Job(fileType: fileType, fileURL: url)
            jobs.append(job)
            jobIDs.append(job.id)
        }

        Task {
            guard await checkConfiguration() else {
                // Remove the jobs we just added — config is invalid.
                let idsToRemove: Set<UUID> = Set(jobIDs)
                jobs.removeAll { idsToRemove.contains($0.id) }
                return
            }
            configurationError = nil

            for jobID in jobIDs {
                Task {
                    await processJob(id: jobID)
                }
            }
        }
    }

    /// Copies the markdown from a completed job to the clipboard.
    /// - Parameter jobID: ID of the completed job.
    public func copyToClipboard(jobID: UUID) {
        guard let job = jobs.first(where: { $0.id == jobID }),
              let markdown: String = job.markdown else { return }
        let pasteboard: NSPasteboard = .general
        pasteboard.clearContents()
        pasteboard.setString(markdown, forType: .string)
    }

    // MARK: - Private

    /// Checks that S3 and Mistral API key are configured.
    /// - Returns: `true` if configuration is valid, `false` otherwise.
    private func checkConfiguration() async -> Bool {
        do {
            let settings: AppSettings = try await settingsGateway.loadSettings()
            guard settings.isS3Configured else {
                configurationError = "Configure your S3 storage in settings."
                return false
            }
            guard let apiKey: String = try await settingsGateway.getSecret(for: .mistralAPIKey),
                  !apiKey.isEmpty else {
                configurationError = "Configure your Mistral API key in settings."
                return false
            }
            return true
        } catch {
            configurationError = error.localizedDescription
            return false
        }
    }

    /// Processes a single job through the pipeline.
    /// - Parameter id: ID of the job to process.
    private func processJob(id: UUID) async {
        updateJob(id: id) { $0.startUpload() }

        do {
            guard let fileURL: URL = jobs.first(where: { $0.id == id })?.fileURL else { return }

            let result: TranscriptionResult = try await useCase.execute(
                fileURL: fileURL
            ) { [weak self] stage in
                guard let self else { return }
                Task { @MainActor in
                    switch stage {
                    case .uploading:
                        break // Already set above
                    case .processing:
                        self.updateJob(id: id) { $0.startProcessing() }
                    }
                }
            }

            updateJob(id: id) { $0.complete(markdown: result.markdown) }
        } catch {
            updateJob(id: id) { $0.fail(error: error.localizedDescription) }
        }

        trimCompletedJobs()
    }

    /// Applies a mutation to the job with the given ID.
    private func updateJob(id: UUID, _ mutation: (inout Job) -> Void) {
        guard let index: Int = jobs.firstIndex(where: { $0.id == id }) else { return }
        mutation(&jobs[index])
    }

    /// Removes the oldest completed/failed jobs beyond the retention limit.
    private func trimCompletedJobs() {
        let completed: [Job] = completedJobs
        guard completed.count > maxCompletedJobs else { return }
        let toRemove: Int = completed.count - maxCompletedJobs
        let idsToRemove: Set<UUID> = Set(
            completed.sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
                .prefix(toRemove)
                .map(\.id)
        )
        jobs.removeAll { idsToRemove.contains($0.id) }
    }
}
