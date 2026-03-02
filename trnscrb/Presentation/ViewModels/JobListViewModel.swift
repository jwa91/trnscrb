import AppKit
import Foundation
import Network

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
    /// Last user-facing drop error (for unsupported file types).
    @Published public var dropError: String?

    /// Maximum number of completed jobs to retain.
    private let maxCompletedJobs: Int = 10
    /// Pipeline orchestrator.
    private let useCase: ProcessFileUseCase
    /// Settings gateway for configuration checks.
    private let settingsGateway: any SettingsGateway
    /// Posts local user notifications when jobs complete or fail.
    private let notificationUseCase: NotifyUserUseCase?
    /// Active processing tasks by job ID so work can be cancelled safely.
    private var runningTasks: [UUID: Task<Void, Never>] = [:]
    /// Jobs queued while offline. They resume automatically when connectivity returns.
    private var queuedOfflineJobs: [UUID: URL] = [:]
    /// Network reachability monitor used for offline queuing.
    private let pathMonitor: NWPathMonitor = NWPathMonitor()
    private let pathMonitorQueue: DispatchQueue = DispatchQueue(
        label: "trnscrb.network-monitor"
    )
    private var isNetworkOnline: Bool = true

    /// Creates a job list view model.
    /// - Parameters:
    ///   - useCase: Pipeline orchestrator for processing files.
    ///   - settingsGateway: Settings gateway for pre-flight configuration checks.
    ///   - notificationUseCase: Optional use case for local user notifications.
    public init(
        useCase: ProcessFileUseCase,
        settingsGateway: any SettingsGateway,
        notificationUseCase: NotifyUserUseCase? = nil
    ) {
        self.useCase = useCase
        self.settingsGateway = settingsGateway
        self.notificationUseCase = notificationUseCase
        startNetworkMonitoring()
    }

    deinit {
        pathMonitor.cancel()
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
    /// Unsupported file types are reported in `dropError`. If S3 or API key is not
    /// configured, sets `configurationError` and removes the queued jobs.
    /// - Parameter urls: Local file URLs from drag-and-drop or file picker.
    public func processFiles(_ urls: [URL]) {
        let unsupportedExts: Set<String> = Set(
            urls
                .map { $0.pathExtension.lowercased() }
                .filter { FileType.from(extension: $0) == nil }
        )
        if unsupportedExts.isEmpty {
            dropError = nil
        } else {
            dropError = unsupportedFileMessage(for: unsupportedExts)
        }

        let validURLs: [(URL, FileType)] = urls.compactMap { url in
            let ext: String = url.pathExtension.lowercased()
            guard let fileType: FileType = FileType.from(extension: ext) else { return nil }
            return (url, fileType)
        }
        guard !validURLs.isEmpty else { return }

        // Create jobs synchronously so callers can inspect them immediately.
        var pendingJobs: [(id: UUID, fileURL: URL)] = []
        for (url, fileType) in validURLs {
            let job: Job = Job(fileType: fileType, fileURL: url)
            jobs.append(job)
            pendingJobs.append((id: job.id, fileURL: url))
        }

        Task {
            guard await checkConfiguration() else {
                // Remove the jobs we just added — config is invalid.
                let idsToRemove: Set<UUID> = Set(pendingJobs.map(\.id))
                jobs.removeAll { idsToRemove.contains($0.id) }
                return
            }
            configurationError = nil

            guard isNetworkOnline else {
                for job in pendingJobs {
                    queueOfflineJob(id: job.id, fileURL: job.fileURL)
                }
                dropError = "You're offline. Jobs will resume automatically once connectivity returns."
                return
            }

            for job in pendingJobs {
                startProcessing(jobID: job.id, fileURL: job.fileURL)
            }
        }
    }

    /// Removes a single job by ID.
    /// - Parameter jobID: ID of the job to remove.
    public func removeJob(id jobID: UUID) {
        cancelTask(for: jobID)
        queuedOfflineJobs[jobID] = nil
        jobs.removeAll { $0.id == jobID }
    }

    /// Removes all completed and failed jobs.
    public func clearCompleted() {
        jobs.removeAll { job in
            switch job.status {
            case .completed, .failed:
                return true
            case .pending, .uploading, .processing:
                return false
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
        defer {
            runningTasks[id] = nil
        }

        do {
            guard let fileURL: URL = jobs.first(where: { $0.id == id })?.fileURL else { return }
            guard runningTasks[id] != nil else { return }
            guard isNetworkOnline else {
                queueOfflineJob(id: id, fileURL: fileURL)
                return
            }

            updateJob(id: id) { $0.startUpload() }

            let result: TranscriptionResult = try await useCase.execute(
                fileURL: fileURL
            ) { [weak self] stage in
                guard let self else { return }
                Task { @MainActor in
                    guard self.runningTasks[id] != nil else { return }
                    switch stage {
                    case .uploading:
                        break // Already set above
                    case .processing:
                        self.updateJob(id: id) { $0.startProcessing() }
                    }
                }
            } onUploadProgress: { [weak self] progress in
                guard let self else { return }
                Task { @MainActor in
                    guard self.runningTasks[id] != nil else { return }
                    self.updateJob(id: id) { $0.updateUploadProgress(progress) }
                }
            }

            guard runningTasks[id] != nil else { return }
            updateJob(id: id) { $0.complete(markdown: result.markdown) }
            await postSuccessNotification(for: result.sourceFileName)
        } catch is CancellationError {
            return
        } catch {
            guard runningTasks[id] != nil else { return }
            if let fileURL: URL = jobs.first(where: { $0.id == id })?.fileURL,
               isOfflineError(error) {
                updateJob(id: id) { $0.requeue() }
                queueOfflineJob(id: id, fileURL: fileURL)
                dropError = "You're offline. Jobs will resume automatically once connectivity returns."
                return
            }
            updateJob(id: id) { $0.fail(error: error.localizedDescription) }
            await postFailureNotification(
                fileName: jobs.first(where: { $0.id == id })?.fileName ?? "File",
                errorMessage: error.localizedDescription
            )
        }

        trimCompletedJobs()
    }

    /// Starts tracking and processing a single job.
    private func startProcessing(jobID: UUID, fileURL: URL) {
        guard isNetworkOnline else {
            queueOfflineJob(id: jobID, fileURL: fileURL)
            return
        }
        cancelTask(for: jobID)
        let task: Task<Void, Never> = Task { [weak self] in
            await self?.processJob(id: jobID)
        }
        runningTasks[jobID] = task
    }

    /// Cancels and removes a tracked processing task.
    private func cancelTask(for jobID: UUID) {
        runningTasks.removeValue(forKey: jobID)?.cancel()
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

    /// Formats a consistent unsupported-file error for the UI.
    private func unsupportedFileMessage(for extensions: Set<String>) -> String {
        let components: [String] = extensions.sorted().map { ext in
            ext.isEmpty ? "unknown" : ".\(ext)"
        }
        let suffix: String = components.joined(separator: ", ")
        return "Unsupported file type: \(suffix)"
    }

    private func startNetworkMonitoring() {
        isNetworkOnline = true
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.isNetworkOnline = path.status == .satisfied
                if self.isNetworkOnline {
                    self.resumeQueuedOfflineJobs()
                }
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }

    private func queueOfflineJob(id: UUID, fileURL: URL) {
        queuedOfflineJobs[id] = fileURL
    }

    private func resumeQueuedOfflineJobs() {
        guard !queuedOfflineJobs.isEmpty else { return }
        let jobsToResume: [(UUID, URL)] = queuedOfflineJobs.map { ($0.key, $0.value) }
        queuedOfflineJobs.removeAll()
        for (jobID, fileURL) in jobsToResume {
            guard jobs.contains(where: { $0.id == jobID }) else { continue }
            startProcessing(jobID: jobID, fileURL: fileURL)
        }
        dropError = nil
    }

    private func isOfflineError(_ error: any Error) -> Bool {
        guard let urlError: URLError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost:
            return true
        default:
            return false
        }
    }

    private func postSuccessNotification(for fileName: String) async {
        await postNotification(
            title: "trnscrb",
            body: "\(fileName) ready — copied or saved based on your settings."
        )
    }

    private func postFailureNotification(fileName: String, errorMessage: String) async {
        await postNotification(
            title: "trnscrb",
            body: "\(fileName) failed: \(errorMessage)"
        )
    }

    private func postNotification(title: String, body: String) async {
        guard let notificationUseCase else { return }
        await notificationUseCase.notify(title: title, body: body)
    }
}
