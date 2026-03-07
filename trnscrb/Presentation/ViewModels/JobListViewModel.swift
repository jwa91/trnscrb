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
    public enum CopyFeedbackTarget: Sendable, Equatable {
        case markdown
        case sourceURL
    }

    public struct CopyFeedback: Sendable, Equatable {
        public let jobID: UUID
        public let target: CopyFeedbackTarget

        public init(jobID: UUID, target: CopyFeedbackTarget) {
            self.jobID = jobID
            self.target = target
        }
    }

    /// All jobs, both active and completed.
    @Published public var jobs: [Job] = []
    /// Currently selected job, used for keyboard actions and notification re-entry.
    @Published public var selectedJobID: UUID?
    /// Error message when S3 or API key is not configured.
    @Published public var configurationError: String?
    /// One-shot routing signal used to open settings after a configuration failure.
    @Published public private(set) var shouldOpenSettings: Bool = false
    /// Last user-facing drop error (for unsupported file types).
    @Published public var dropError: String?
    /// User-facing status for jobs queued while offline.
    @Published public var offlineStatusMessage: String?
    /// Job copy feedback currently shown in the UI.
    @Published public private(set) var copyFeedback: CopyFeedback?

    /// Maximum number of completed jobs to retain.
    private let maxCompletedJobs: Int = 10
    /// Pipeline orchestrator.
    private let useCase: ProcessFileUseCase
    /// Settings gateway for configuration checks.
    private let settingsGateway: any SettingsGateway
    /// Validates and prepares the configured output folder before processing starts.
    private let outputFolderGateway: any OutputFolderGateway
    /// Posts local user notifications when jobs complete or fail.
    private let notificationUseCase: NotifyUserUseCase?
    /// Opens the configured output folder in Finder.
    private let openFolder: @Sendable (URL) -> Void
    /// Active processing tasks by job ID so work can be cancelled safely.
    private var runningTasks: [UUID: Task<Void, Never>] = [:]
    /// Jobs queued while offline. They resume automatically when connectivity returns.
    private var queuedOfflineJobs: [UUID: URL] = [:]
    /// Short-lived feedback timer for the copied confirmation.
    private var copyFeedbackTask: Task<Void, Never>?
    /// Duration that the copied confirmation remains visible.
    private let copyFeedbackDuration: Duration
    /// Network reachability monitor used for offline queuing.
    private let pathMonitor: NWPathMonitor = NWPathMonitor()
    private let pathMonitorQueue: DispatchQueue = DispatchQueue(
        label: "trnscrb.network-monitor"
    )
    private var isNetworkOnline: Bool = true
    /// Snapshot of notification formatting options captured at job start.
    private var jobCopyToClipboardPreferences: [UUID: Bool] = [:]

    /// Creates a job list view model.
    /// - Parameters:
    ///   - useCase: Pipeline orchestrator for processing files.
    ///   - settingsGateway: Settings gateway for pre-flight configuration checks.
    ///   - notificationUseCase: Optional use case for local user notifications.
    public convenience init(
        useCase: ProcessFileUseCase,
        settingsGateway: any SettingsGateway,
        outputFolderGateway: any OutputFolderGateway,
        notificationUseCase: NotifyUserUseCase? = nil,
        copyFeedbackDuration: Duration = .seconds(1.5),
        openFolder: @escaping @Sendable (URL) -> Void = { url in
            NSWorkspace.shared.open(url)
        }
    ) {
        self.init(
            useCase: useCase,
            settingsGateway: settingsGateway,
            outputFolderGateway: outputFolderGateway,
            notificationUseCase: notificationUseCase,
            copyFeedbackDuration: copyFeedbackDuration,
            openFolder: openFolder,
            shouldStartNetworkMonitoring: true
        )
    }

    init(
        useCase: ProcessFileUseCase,
        settingsGateway: any SettingsGateway,
        outputFolderGateway: any OutputFolderGateway,
        notificationUseCase: NotifyUserUseCase? = nil,
        copyFeedbackDuration: Duration = .seconds(1.5),
        openFolder: @escaping @Sendable (URL) -> Void = { url in
            NSWorkspace.shared.open(url)
        },
        shouldStartNetworkMonitoring: Bool
    ) {
        self.useCase = useCase
        self.settingsGateway = settingsGateway
        self.outputFolderGateway = outputFolderGateway
        self.notificationUseCase = notificationUseCase
        self.copyFeedbackDuration = copyFeedbackDuration
        self.openFolder = openFolder
        if shouldStartNetworkMonitoring {
            startNetworkMonitoring()
        }
    }

    deinit {
        copyFeedbackTask?.cancel()
        pathMonitor.cancel()
    }

    /// Jobs that are still active (pending, uploading, or processing).
    public var activeJobs: [Job] {
        jobs.filter { job in
            switch job.status {
            case .pending, .processing, .mirroring, .delivering:
                return true
            case .completed, .failed:
                return false
            }
        }
    }

    /// Jobs that have completed or failed, newest first.
    public var completedJobs: [Job] {
        jobs
            .filter { job in
                switch job.status {
                case .completed, .failed:
                    return true
                case .pending, .processing, .mirroring, .delivering:
                    return false
                }
            }
            .sorted { lhs, rhs in
                let lhsCompletedAt: Date = lhs.completedAt ?? lhs.createdAt
                let rhsCompletedAt: Date = rhs.completedAt ?? rhs.createdAt
                if lhsCompletedAt != rhsCompletedAt {
                    return lhsCompletedAt > rhsCompletedAt
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    /// Jobs in the same order they are rendered in the menu panel.
    public var visibleJobs: [Job] {
        activeJobs + completedJobs
    }

    /// Selects a job so the UI can reveal it after keyboard actions or notification re-entry.
    public func selectJob(id: UUID?) {
        guard let id else {
            selectedJobID = nil
            return
        }
        guard jobs.contains(where: { $0.id == id }) else { return }
        selectedJobID = id
    }

    /// Selects the next visible job in keyboard navigation order.
    public func selectNextVisibleJob() {
        let orderedIDs: [UUID] = visibleJobs.map(\.id)
        guard !orderedIDs.isEmpty else {
            selectedJobID = nil
            return
        }
        guard let selectedJobID,
              let selectedIndex: Int = orderedIDs.firstIndex(of: selectedJobID) else {
            self.selectedJobID = orderedIDs.first
            return
        }
        self.selectedJobID = orderedIDs[min(selectedIndex + 1, orderedIDs.count - 1)]
    }

    /// Selects the previous visible job in keyboard navigation order.
    public func selectPreviousVisibleJob() {
        let orderedIDs: [UUID] = visibleJobs.map(\.id)
        guard !orderedIDs.isEmpty else {
            selectedJobID = nil
            return
        }
        guard let selectedJobID,
              let selectedIndex: Int = orderedIDs.firstIndex(of: selectedJobID) else {
            self.selectedJobID = orderedIDs.last
            return
        }
        self.selectedJobID = orderedIDs[max(selectedIndex - 1, 0)]
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
        AppLog.ui.info(
            "Accepted batch with \(validURLs.count, privacy: .public) valid file(s) out of \(urls.count, privacy: .public)"
        )

        // Create jobs synchronously so callers can inspect them immediately.
        var pendingJobs: [(id: UUID, fileURL: URL)] = []
        var newJobs: [Job] = []
        for (url, fileType) in validURLs {
            let job: Job = Job(fileType: fileType, fileURL: url)
            newJobs.append(job)
            pendingJobs.append((id: job.id, fileURL: url))
        }
        jobs = jobs + newJobs

        Task {
            guard let configuration: ProcessingConfiguration = await checkConfiguration() else {
                // Remove the jobs we just added — config is invalid.
                let idsToRemove: Set<UUID> = Set(pendingJobs.map(\.id))
                for jobID in idsToRemove {
                    jobCopyToClipboardPreferences[jobID] = nil
                }
                jobs = jobs.filter { !idsToRemove.contains($0.id) }
                return
            }
            configurationError = nil
            for job in pendingJobs {
                jobCopyToClipboardPreferences[job.id] = configuration.copyToClipboard
            }

            guard isNetworkOnline else {
                for job in pendingJobs {
                    queueOfflineJob(id: job.id, fileURL: job.fileURL)
                }
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
        jobCopyToClipboardPreferences[jobID] = nil
        if selectedJobID == jobID {
            selectedJobID = nil
        }
        if copyFeedback?.jobID == jobID {
            copyFeedback = nil
        }
        jobs = jobs.filter { $0.id != jobID }
    }

    /// Removes the selected job or falls back to the default Delete target.
    public func removeSelectedOrMostRecentJob() {
        if let selectedJobID {
            removeJob(id: selectedJobID)
            return
        }
        if let fallbackID: UUID = completedJobs.first?.id ?? activeJobs.first?.id {
            removeJob(id: fallbackID)
        }
    }

    /// Removes all completed and failed jobs.
    public func clearCompleted() {
        let clearedIDs: Set<UUID> = Set(completedJobs.map(\.id))
        for jobID in clearedIDs {
            jobCopyToClipboardPreferences[jobID] = nil
        }
        if let copyFeedback, clearedIDs.contains(copyFeedback.jobID) {
            self.copyFeedback = nil
        }
        jobs = jobs.filter { job in
            switch job.status {
            case .completed, .failed:
                return false
            case .pending, .processing, .mirroring, .delivering:
                return true
            }
        }
    }

    /// Clears the current configuration error banner.
    public func clearConfigurationError() {
        configurationError = nil
    }

    /// Consumes the one-shot request to route the menu panel into settings.
    public func consumeSettingsNavigation() {
        shouldOpenSettings = false
    }

    /// Clears the current drop error banner.
    public func clearDropError() {
        dropError = nil
    }

    /// Clears the current offline-status banner.
    public func clearOfflineStatus() {
        offlineStatusMessage = nil
    }

    /// Copies the markdown from a completed job to the clipboard.
    /// - Parameter jobID: ID of the completed job.
    public func copyToClipboard(jobID: UUID) {
        guard let job = jobs.first(where: { $0.id == jobID }),
              let markdown: String = job.markdown else { return }
        writeToPasteboard(markdown, jobID: jobID, target: .markdown)
    }

    /// Copies the remote source URL from a completed job to the clipboard.
    /// - Parameter jobID: ID of the completed job.
    public func copySourceURLToClipboard(jobID: UUID) {
        guard let sourceURL: URL = jobs.first(where: { $0.id == jobID })?.remoteSourceURL else { return }
        writeToPasteboard(sourceURL.absoluteString, jobID: jobID, target: .sourceURL)
    }

    private func writeToPasteboard(_ value: String, jobID: UUID, target: CopyFeedbackTarget) {
        let pasteboard: NSPasteboard = .general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        copyFeedback = CopyFeedback(jobID: jobID, target: target)
        copyFeedbackTask?.cancel()
        let feedbackDuration: Duration = copyFeedbackDuration
        copyFeedbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: feedbackDuration)
            guard let self,
                  self.copyFeedback == CopyFeedback(jobID: jobID, target: target) else { return }
            self.copyFeedback = nil
        }
    }

    /// Reveals the saved markdown file for a completed job in Finder.
    /// - Parameter jobID: ID of the completed job.
    public func revealInFinder(jobID: UUID) {
        guard let fileURL: URL = jobs.first(where: { $0.id == jobID })?.savedFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    /// Opens the saved markdown file for a completed job in the default app.
    /// - Parameter jobID: ID of the completed job.
    public func openSavedFile(jobID: UUID) {
        guard let fileURL: URL = jobs.first(where: { $0.id == jobID })?.savedFileURL else { return }
        NSWorkspace.shared.open(fileURL)
    }

    /// Opens the configured markdown output folder in Finder.
    public func openConfiguredSaveFolder() async {
        do {
            let settings: AppSettings = try await settingsGateway.loadSettings().normalizedForUse
            let folderURL: URL = try outputFolderGateway.prepareOutputFolder(path: settings.saveFolderPath)
            openFolder(folderURL)
        } catch {
            configurationError = error.localizedDescription
            shouldOpenSettings = true
        }
    }

    // MARK: - Private

    /// Validates credentials and output folder before processing.
    /// - Returns: Processing configuration if valid, `nil` otherwise.
    private func checkConfiguration() async -> ProcessingConfiguration? {
        do {
            let settings: AppSettings = try await settingsGateway.loadSettings().normalizedForUse

            if settings.requiresCloudCredentials {
                guard let apiKey: String = try await settingsGateway.getSecret(for: .mistralAPIKey),
                      !apiKey.trimmedCredentialValue.isEmpty else {
                    configurationError = "Configure your Mistral API key in Settings."
                    return nil
                }
            }

            if settings.requiresS3Credentials {
                guard settings.isS3Configured else {
                    configurationError = "Configure your S3 endpoint, access key, and bucket in Settings."
                    shouldOpenSettings = true
                    return nil
                }
                guard let s3SecretKey: String = try await settingsGateway.getSecret(for: .s3SecretKey),
                      !s3SecretKey.trimmedCredentialValue.isEmpty else {
                    configurationError = "Configure your S3 secret key in Settings."
                    shouldOpenSettings = true
                    return nil
                }
            }

            do {
                _ = try outputFolderGateway.prepareOutputFolder(path: settings.saveFolderPath)
            } catch {
                configurationError = error.localizedDescription
                shouldOpenSettings = true
                return nil
            }
            return ProcessingConfiguration(copyToClipboard: settings.copyToClipboard)
        } catch {
            configurationError = error.localizedDescription
            return nil
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
            AppLog.ui.info("Job \(id.uuidString, privacy: .public) started for \(fileURL.lastPathComponent, privacy: .public)")
            guard runningTasks[id] != nil else { return }
            guard isNetworkOnline else {
                queueOfflineJob(id: id, fileURL: fileURL)
                return
            }

            updateJob(id: id) { $0.startProcessing() }

            let result: TranscriptionResult = try await useCase.execute(
                fileURL: fileURL
            ) { [weak self] stage in
                guard let self else { return }
                Task { @MainActor in
                    guard self.runningTasks[id] != nil else { return }
                    switch stage {
                    case .processing:
                        break // Already set above
                    case .mirroring:
                        self.updateJob(id: id) { $0.startMirroring() }
                    case .delivery:
                        self.updateJob(id: id) { $0.startDelivery() }
                    }
                }
            } onMirroringProgress: { [weak self] progress in
                guard let self else { return }
                Task { @MainActor in
                    guard self.runningTasks[id] != nil else { return }
                    self.updateJob(id: id) { $0.updateMirroringProgress(progress) }
                }
            }

            guard runningTasks[id] != nil else { return }
            guard let savedFileURL: URL = result.savedFileURL else {
                throw FileDeliveryError.writeFailed("Markdown file was not saved.")
            }
            let copyToClipboard: Bool = jobCopyToClipboardPreferences[id] ?? false
            AppLog.ui.info("Finalizing UI completion for job \(id.uuidString, privacy: .public)")
            guard completeJob(
                id: id,
                markdown: result.markdown,
                mirrorWarnings: result.mirrorWarnings,
                deliveryWarnings: result.deliveryWarnings,
                savedFileURL: savedFileURL,
                remoteSourceURL: result.remoteSourceURL
            ) else {
                AppLog.ui.error("Job \(id.uuidString, privacy: .public) finished, but UI state could not be finalized")
                return
            }
            AppLog.ui.info("UI completion finalized for job \(id.uuidString, privacy: .public)")
            AppLog.ui.info("Job \(id.uuidString, privacy: .public) completed")
            selectJob(id: id)
            await postSuccessNotification(
                for: result.sourceFileName,
                jobID: id,
                savedFileURL: savedFileURL,
                copyToClipboard: copyToClipboard,
                mirrorWarnings: result.mirrorWarnings,
                deliveryWarnings: result.deliveryWarnings
            )
            jobCopyToClipboardPreferences[id] = nil
        } catch is CancellationError {
            AppLog.ui.info("Job \(id.uuidString, privacy: .public) cancelled")
            return
        } catch {
            guard runningTasks[id] != nil else { return }
            if let fileURL: URL = jobs.first(where: { $0.id == id })?.fileURL,
               isOfflineError(error) {
                updateJob(id: id) { $0.requeue() }
                queueOfflineJob(id: id, fileURL: fileURL)
                return
            }
            AppLog.ui.error(
                "Job \(id.uuidString, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
            )
            updateJob(id: id) { $0.fail(error: error.localizedDescription) }
            selectJob(id: id)
            await postFailureNotification(
                fileName: jobs.first(where: { $0.id == id })?.fileName ?? "File",
                jobID: id,
                errorMessage: error.localizedDescription
            )
            jobCopyToClipboardPreferences[id] = nil
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
        var updatedJobs: [Job] = jobs
        mutation(&updatedJobs[index])
        jobs = updatedJobs
    }

    /// Finalizes a successfully processed job even if async stage callbacks arrive late.
    ///
    /// Stage updates are reported via async hops back to the main actor. If the
    /// pipeline completes before the final delivery-stage hop runs, the job can
    /// still be in an earlier active state and a direct call to `Job.complete()`
    /// would be ignored by the state machine.
    private func completeJob(
        id: UUID,
        markdown: String,
        mirrorWarnings: [String],
        deliveryWarnings: [String],
        savedFileURL: URL?,
        remoteSourceURL: URL?
    ) -> Bool {
        guard let index: Int = jobs.firstIndex(where: { $0.id == id }) else { return false }
        var updatedJobs: [Job] = jobs

        switch updatedJobs[index].status {
        case .pending:
            updatedJobs[index].startProcessing()
        case .processing:
            updatedJobs[index].startDelivery()
        case .mirroring:
            updatedJobs[index].startDelivery()
        case .delivering:
            break
        case .completed:
            return true
        case .failed:
            return false
        }

        updatedJobs[index].complete(
            markdown: markdown,
            mirrorWarnings: mirrorWarnings,
            deliveryWarnings: deliveryWarnings,
            savedFileURL: savedFileURL,
            remoteSourceURL: remoteSourceURL
        )
        jobs = updatedJobs

        if case .completed = updatedJobs[index].status {
            return true
        }
        return false
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
        for jobID in idsToRemove {
            jobCopyToClipboardPreferences[jobID] = nil
        }
        jobs = jobs.filter { !idsToRemove.contains($0.id) }
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
                self?.handleNetworkStatusChange(isOnline: path.status == .satisfied)
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }

    func handleNetworkStatusChange(isOnline: Bool) {
        isNetworkOnline = isOnline
        if isOnline {
            resumeQueuedOfflineJobs()
        }
    }

    private func queueOfflineJob(id: UUID, fileURL: URL) {
        queuedOfflineJobs[id] = fileURL
        offlineStatusMessage = offlineMessage
    }

    private func resumeQueuedOfflineJobs() {
        guard !queuedOfflineJobs.isEmpty else { return }
        let jobsToResume: [(UUID, URL)] = queuedOfflineJobs.map { ($0.key, $0.value) }
        queuedOfflineJobs.removeAll()
        for (jobID, fileURL) in jobsToResume {
            guard jobs.contains(where: { $0.id == jobID }) else { continue }
            startProcessing(jobID: jobID, fileURL: fileURL)
        }
        offlineStatusMessage = nil
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

    private func postSuccessNotification(
        for fileName: String,
        jobID: UUID,
        savedFileURL: URL,
        copyToClipboard: Bool,
        mirrorWarnings: [String],
        deliveryWarnings: [String]
    ) async {
        await postNotification(
            identifier: jobID.uuidString,
            title: "trnscrb",
            body: successNotificationBody(
                fileName: fileName,
                savedFileURL: savedFileURL,
                copyToClipboard: copyToClipboard,
                mirrorWarnings: mirrorWarnings,
                deliveryWarnings: deliveryWarnings
            )
        )
    }

    private func postFailureNotification(fileName: String, jobID: UUID, errorMessage: String) async {
        await postNotification(
            identifier: jobID.uuidString,
            title: "trnscrb",
            body: "\(fileName) failed: \(errorMessage)"
        )
    }

    private func postNotification(identifier: String, title: String, body: String) async {
        guard let notificationUseCase else { return }
        await notificationUseCase.notify(title: title, body: body, identifier: identifier)
    }

    private func successNotificationBody(
        fileName: String,
        savedFileURL: URL,
        copyToClipboard: Bool,
        mirrorWarnings: [String],
        deliveryWarnings: [String]
    ) -> String {
        let savedPath: String = savedFileURL.path()
        var components: [String] = []

        if deliveryWarnings.isEmpty {
            if copyToClipboard {
                components.append("\(fileName) saved to \(savedPath) and copied to clipboard.")
            } else {
                components.append("\(fileName) saved to \(savedPath).")
            }
        } else if copyToClipboard {
            components.append("\(fileName) saved to \(savedPath), but copying to the clipboard failed.")
        } else {
            components.append("\(fileName) saved to \(savedPath).")
            components.append(contentsOf: deliveryWarnings)
        }

        components.append(contentsOf: mirrorWarnings)
        return components.joined(separator: " ")
    }

    private struct ProcessingConfiguration {
        let copyToClipboard: Bool
    }

    private var offlineMessage: String {
        "You're offline. Jobs will resume automatically once connectivity returns."
    }
}
