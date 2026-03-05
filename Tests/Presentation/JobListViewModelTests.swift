import Foundation
import Testing

@testable import trnscrb

@Suite(.serialized)
@MainActor
struct JobListViewModelTests {
    private final class LockedOpenedFolderRecorder: @unchecked Sendable {
        private let lock: NSLock = NSLock()
        private var urls: [URL] = []

        func append(_ url: URL) {
            lock.lock()
            urls.append(url)
            lock.unlock()
        }

        func snapshot() -> [URL] {
            lock.lock()
            defer { lock.unlock() }
            return urls
        }
    }

    private func configuredSettingsGateway() -> MockSettingsGateway {
        let settings: AppSettings = AppSettings(
            s3EndpointURL: "https://s3.example.com",
            s3AccessKey: "AKID",
            s3BucketName: "bucket"
        )
        let secrets: [SecretKey: String] = [
            .mistralAPIKey: "mk-test",
            .s3SecretKey: "sk-test"
        ]
        return MockSettingsGateway(settings: settings, secrets: secrets)
    }

    private func makeViewModel(
        storage: MockStorageGateway = MockStorageGateway(),
        delivery: MockDeliveryGateway = MockDeliveryGateway(
            savedFileURL: URL(filePath: "/tmp/trnscrb-output.md")
        ),
        settings: MockSettingsGateway,
        notificationGateway: MockNotificationGateway = MockNotificationGateway(),
        outputFolderGateway: MockOutputFolderGateway = MockOutputFolderGateway(),
        copyFeedbackDuration: Duration = .seconds(1.5),
        openFolder: @escaping @Sendable (URL) -> Void = { _ in },
        isLocalModeAvailable: @escaping @Sendable () -> Bool = {
            if #available(macOS 26, *) {
                return true
            }
            return false
        }
    ) -> (
        JobListViewModel,
        MockStorageGateway,
        MockDeliveryGateway,
        MockSettingsGateway,
        MockNotificationGateway,
        MockOutputFolderGateway
    ) {
        let audio: MockTranscriptionGateway = MockTranscriptionGateway(
            supportedExtensions: FileType.audioExtensions
        )
        let ocr: MockTranscriptionGateway = MockTranscriptionGateway(
            supportedExtensions: FileType.pdfExtensions.union(FileType.imageExtensions)
        )
        let useCase: ProcessFileUseCase = ProcessFileUseCase(
            storage: storage,
            transcribers: [audio, ocr],
            delivery: delivery,
            settings: settings
        )
        let vm: JobListViewModel = JobListViewModel(
            useCase: useCase,
            settingsGateway: settings,
            outputFolderGateway: outputFolderGateway,
            notificationUseCase: NotifyUserUseCase(gateway: notificationGateway),
            copyFeedbackDuration: copyFeedbackDuration,
            openFolder: openFolder,
            isLocalModeAvailable: isLocalModeAvailable,
            shouldStartNetworkMonitoring: false
        )
        return (vm, storage, delivery, settings, notificationGateway, outputFolderGateway)
    }

    private func makeViewModel(
        storage: MockStorageGateway = MockStorageGateway(),
        delivery: MockDeliveryGateway = MockDeliveryGateway(
            savedFileURL: URL(filePath: "/tmp/trnscrb-output.md")
        ),
        copyFeedbackDuration: Duration = .seconds(1.5),
        openFolder: @escaping @Sendable (URL) -> Void = { _ in },
        isLocalModeAvailable: @escaping @Sendable () -> Bool = {
            if #available(macOS 26, *) {
                return true
            }
            return false
        }
    ) -> (
        JobListViewModel,
        MockStorageGateway,
        MockDeliveryGateway,
        MockSettingsGateway,
        MockNotificationGateway,
        MockOutputFolderGateway
    ) {
        makeViewModel(
            storage: storage,
            delivery: delivery,
            settings: configuredSettingsGateway(),
            copyFeedbackDuration: copyFeedbackDuration,
            openFolder: openFolder,
            isLocalModeAvailable: isLocalModeAvailable
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        _ condition: @escaping () -> Bool
    ) async -> Bool {
        let clock: ContinuousClock = ContinuousClock()
        let deadline: ContinuousClock.Instant = clock.now + timeout
        while !condition() {
            if clock.now >= deadline {
                return false
            }
            await Task.yield()
        }
        return true
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        _ condition: @escaping () async -> Bool
    ) async -> Bool {
        let clock: ContinuousClock = ContinuousClock()
        let deadline: ContinuousClock.Instant = clock.now + timeout
        while !(await condition()) {
            if clock.now >= deadline {
                return false
            }
            await Task.yield()
        }
        return true
    }

    // MARK: - File validation

    @Test func rejectsUnsupportedFileType() async {
        let (vm, _, _, _, _, _) = makeViewModel()
        vm.processFiles([URL(filePath: "/tmp/file.xyz")])
        #expect(vm.jobs.isEmpty)
        #expect(vm.dropError == "Unsupported file type: .xyz")
    }

    @Test func createsJobForSupportedFile() async {
        let (vm, _, _, _, _, _) = makeViewModel()
        vm.processFiles([URL(filePath: "/tmp/test.mp3")])
        #expect(vm.jobs.count == 1)
        #expect(vm.jobs[0].fileType == .audio)
        #expect(vm.jobs[0].fileName == "test.mp3")
    }

    @Test func createsJobsForMultipleFiles() async {
        let (vm, _, _, _, _, _) = makeViewModel()
        vm.processFiles([
            URL(filePath: "/tmp/audio.mp3"),
            URL(filePath: "/tmp/doc.pdf"),
            URL(filePath: "/tmp/photo.png")
        ])
        #expect(vm.jobs.count == 3)
    }

    @Test func filtersUnsupportedFromMixedBatch() async {
        let (vm, _, _, _, _, _) = makeViewModel()
        vm.processFiles([
            URL(filePath: "/tmp/good.mp3"),
            URL(filePath: "/tmp/bad.xyz"),
            URL(filePath: "/tmp/good.pdf")
        ])
        #expect(vm.jobs.count == 2)
        #expect(vm.dropError == "Unsupported file type: .xyz")
    }

    @Test func mixedOfflineBatchKeepsValidationErrorSeparateFromOfflineStatus() async {
        let (vm, _, _, _, _, _) = makeViewModel()
        vm.handleNetworkStatusChange(isOnline: false)

        vm.processFiles([
            URL(filePath: "/tmp/good.mp3"),
            URL(filePath: "/tmp/bad.xyz")
        ])

        let queued: Bool = await waitUntil {
            vm.jobs.count == 1
                && vm.offlineStatusMessage == "You're offline. Jobs will resume automatically once connectivity returns."
        }

        #expect(queued)
        #expect(vm.dropError == "Unsupported file type: .xyz")

        vm.clearOfflineStatus()

        #expect(vm.offlineStatusMessage == nil)
        #expect(vm.dropError == "Unsupported file type: .xyz")
    }

    @Test func resumingQueuedOfflineJobsClearsOnlyOfflineStatus() async {
        let (vm, _, _, _, _, _) = makeViewModel()
        vm.handleNetworkStatusChange(isOnline: false)

        vm.processFiles([
            URL(filePath: "/tmp/good.mp3"),
            URL(filePath: "/tmp/bad.xyz")
        ])

        let queued: Bool = await waitUntil {
            vm.jobs.count == 1
                && vm.offlineStatusMessage == "You're offline. Jobs will resume automatically once connectivity returns."
        }
        #expect(queued)

        vm.handleNetworkStatusChange(isOnline: true)

        let resumed: Bool = await waitUntil(timeout: .seconds(2)) {
            vm.activeJobs.isEmpty && vm.completedJobs.count == 1 && vm.offlineStatusMessage == nil
        }

        #expect(resumed)
        #expect(vm.dropError == "Unsupported file type: .xyz")
    }

    @Test func mixedOfflineBatchShowsOfflineStatusWithoutLosingValidationError() async {
        let storage: MockStorageGateway = MockStorageGateway(
            uploadError: URLError(.notConnectedToInternet)
        )
        let (vm, _, _, _, _, _) = makeViewModel(storage: storage)

        vm.processFiles([
            URL(filePath: "/tmp/good.mp3"),
            URL(filePath: "/tmp/bad.xyz")
        ])

        let queued: Bool = await waitUntil(timeout: .seconds(2)) {
            vm.offlineStatusMessage != nil && vm.jobs.count == 1
        }

        #expect(queued)
        #expect(vm.dropError == "Unsupported file type: .xyz")
        #expect(
            vm.offlineStatusMessage
                == "You're offline. Jobs will resume automatically once connectivity returns."
        )
    }

    @Test func clearingOfflineStatusDoesNotAffectValidationError() async {
        let storage: MockStorageGateway = MockStorageGateway(
            uploadError: URLError(.notConnectedToInternet)
        )
        let (vm, _, _, _, _, _) = makeViewModel(storage: storage)

        vm.processFiles([
            URL(filePath: "/tmp/good.mp3"),
            URL(filePath: "/tmp/bad.xyz")
        ])

        let queued: Bool = await waitUntil(timeout: .seconds(2)) {
            vm.offlineStatusMessage != nil && vm.dropError == "Unsupported file type: .xyz"
        }

        #expect(queued)

        vm.clearOfflineStatus()

        #expect(vm.offlineStatusMessage == nil)
        #expect(vm.dropError == "Unsupported file type: .xyz")
    }

    @Test func resumingQueuedOfflineJobsClearsOnlyOfflineStatusMessage() async {
        let storage: MockStorageGateway = MockStorageGateway(
            uploadError: URLError(.notConnectedToInternet)
        )
        let (vm, _, _, _, _, _) = makeViewModel(storage: storage)

        vm.processFiles([
            URL(filePath: "/tmp/good.mp3"),
            URL(filePath: "/tmp/bad.xyz")
        ])

        let queued: Bool = await waitUntil(timeout: .seconds(2)) {
            vm.offlineStatusMessage != nil && vm.jobs.count == 1
        }

        #expect(queued)

        await storage.setUploadError(nil)
        vm.handleNetworkStatusChange(isOnline: true)

        let completed: Bool = await waitUntil(timeout: .seconds(2)) {
            vm.activeJobs.isEmpty && vm.completedJobs.count == 1
        }

        #expect(completed)
        #expect(vm.offlineStatusMessage == nil)
        #expect(vm.dropError == "Unsupported file type: .xyz")
    }

    // MARK: - Configuration checks

    @Test func setsConfigErrorWhenS3NotConfigured() async {
        let settings: MockSettingsGateway = MockSettingsGateway(
            secrets: [.mistralAPIKey: "mk-test"]
        )
        // s3EndpointURL is empty by default — not configured
        let (vm, _, _, _, _, _) = makeViewModel(
            settings: settings,
            isLocalModeAvailable: { false }
        )

        vm.processFiles([URL(filePath: "/tmp/test.mp3")])
        let completed: Bool = await waitUntil {
            vm.configurationError != nil && vm.jobs.isEmpty
        }

        #expect(completed)
        #expect(vm.configurationError != nil)
        #expect(vm.jobs.isEmpty)
    }

    @Test func setsConfigErrorWhenAPIKeyMissing() async {
        let settings: MockSettingsGateway = MockSettingsGateway(
            settings: AppSettings(
                s3EndpointURL: "https://s3.example.com",
                s3AccessKey: "AKID",
                s3BucketName: "bucket"
            ),
            secrets: [.s3SecretKey: "sk-test"]
        )
        // No Mistral API key
        let (vm, _, _, _, _, _) = makeViewModel(
            settings: settings,
            isLocalModeAvailable: { false }
        )

        vm.processFiles([URL(filePath: "/tmp/test.mp3")])
        let completed: Bool = await waitUntil {
            vm.configurationError != nil && vm.jobs.isEmpty
        }

        #expect(completed)
        #expect(vm.configurationError != nil)
        #expect(vm.jobs.isEmpty)
    }

    @Test func setsConfigErrorWhenS3SecretMissing() async {
        let settings: MockSettingsGateway = MockSettingsGateway(
            settings: AppSettings(
                s3EndpointURL: "https://s3.example.com",
                s3AccessKey: "AKID",
                s3BucketName: "bucket"
            ),
            secrets: [.mistralAPIKey: "mk-test"]
        )
        let (vm, _, _, _, _, _) = makeViewModel(
            settings: settings,
            isLocalModeAvailable: { false }
        )

        vm.processFiles([URL(filePath: "/tmp/test.mp3")])
        let completed: Bool = await waitUntil {
            vm.configurationError != nil && vm.jobs.isEmpty
        }

        #expect(completed)
        #expect(vm.configurationError == "Configure your S3 secret key in settings.")
        #expect(vm.jobs.isEmpty)
    }

    @Test func localOnlyConfigurationSkipsCloudChecksWhenLocalModeAvailable() async {
        let settings: MockSettingsGateway = MockSettingsGateway(
            settings: AppSettings(
                audioProviderMode: .localApple,
                pdfProviderMode: .localApple,
                imageProviderMode: .localApple
            )
        )
        let storage: MockStorageGateway = MockStorageGateway()
        let delivery: MockDeliveryGateway = MockDeliveryGateway(
            savedFileURL: URL(filePath: "/tmp/local-only.md")
        )
        let localAudio: MockTranscriptionGateway = MockTranscriptionGateway(
            supportedExtensions: FileType.audioExtensions,
            providerMode: .localApple,
            sourceKind: .localFile,
            processResult: "# Local Audio"
        )
        let localOCR: MockTranscriptionGateway = MockTranscriptionGateway(
            supportedExtensions: FileType.pdfExtensions.union(FileType.imageExtensions),
            providerMode: .localApple,
            sourceKind: .localFile,
            processResult: "# Local OCR"
        )
        let useCase: ProcessFileUseCase = ProcessFileUseCase(
            storage: storage,
            transcribers: [localAudio, localOCR],
            delivery: delivery,
            settings: settings,
            isLocalModeAvailable: { true }
        )
        let vm: JobListViewModel = JobListViewModel(
            useCase: useCase,
            settingsGateway: settings,
            outputFolderGateway: MockOutputFolderGateway(),
            isLocalModeAvailable: { true },
            shouldStartNetworkMonitoring: false
        )

        vm.processFiles([URL(filePath: "/tmp/local.mp3")])

        let completed: Bool = await waitUntil(timeout: .seconds(2)) {
            vm.activeJobs.isEmpty && vm.completedJobs.count == 1
        }

        #expect(completed)
        #expect(vm.configurationError == nil)
        #expect(await storage.recordedUploadAttemptCount() == 0)
    }

    @Test func localOnlyConfigurationRequiresCloudChecksWhenLocalModeUnavailable() async {
        let settings: MockSettingsGateway = MockSettingsGateway(
            settings: AppSettings(
                audioProviderMode: .localApple,
                pdfProviderMode: .localApple,
                imageProviderMode: .localApple
            )
        )
        let (vm, _, _, _, _, _) = makeViewModel(
            settings: settings,
            isLocalModeAvailable: { false }
        )

        vm.processFiles([URL(filePath: "/tmp/local.mp3")])
        let completed: Bool = await waitUntil {
            vm.configurationError != nil && vm.jobs.isEmpty
        }

        #expect(completed)
        #expect(vm.configurationError == "Configure your S3 storage in settings.")
    }

    @Test func invalidSaveFolderPreventsProcessingAndRequestsSettings() async {
        let settings: MockSettingsGateway = configuredSettingsGateway()
        let outputFolderGateway: MockOutputFolderGateway = MockOutputFolderGateway()
        outputFolderGateway.setError(OutputFolderError.notWritable)
        let (vm, _, delivery, _, _, _) = makeViewModel(
            settings: settings,
            outputFolderGateway: outputFolderGateway
        )

        vm.processFiles([URL(filePath: "/tmp/test.mp3")])

        let completed: Bool = await waitUntil {
            vm.configurationError == OutputFolderError.notWritable.localizedDescription
                && vm.jobs.isEmpty
                && vm.shouldOpenSettings
        }

        #expect(completed)
        #expect(await delivery.recordedDeliveredResults().isEmpty)

        vm.consumeSettingsNavigation()
        #expect(!vm.shouldOpenSettings)
    }

    // MARK: - Completed jobs history

    @Test func completedJobsListHasMaxTenItems() async {
        let (vm, _, _, _, _, _) = makeViewModel()

        // Process 12 files
        for i in 0..<12 {
            vm.processFiles([URL(filePath: "/tmp/file\(i).mp3")])
        }
        let didComplete: Bool = await waitUntil(timeout: .seconds(2)) {
            vm.activeJobs.isEmpty && vm.completedJobs.count == 10
        }

        #expect(didComplete)
        let completed: [Job] = vm.completedJobs
        #expect(completed.count <= 10)
    }

    @Test func completedJobsAreSortedNewestFirst() async throws {
        let (vm, _, _, _, _, _) = makeViewModel()

        var older: Job = Job(fileType: .audio, fileURL: URL(filePath: "/tmp/older.mp3"))
        older.startUpload()
        older.startProcessing()
        older.complete(markdown: "# older")

        try await Task.sleep(for: .milliseconds(10))

        var newer: Job = Job(fileType: .audio, fileURL: URL(filePath: "/tmp/newer.mp3"))
        newer.startUpload()
        newer.startProcessing()
        newer.complete(markdown: "# newer")

        vm.jobs = [older, newer]

        #expect(vm.completedJobs.map(\.fileName) == ["newer.mp3", "older.mp3"])
    }

    // MARK: - Computed properties

    @Test func activeJobsFiltersCorrectly() async {
        let (vm, _, _, _, _, _) = makeViewModel()
        vm.processFiles([URL(filePath: "/tmp/test.mp3")])
        // Job should be active immediately after creation
        #expect(vm.activeJobs.count == 1)
    }

    @Test func multiFileBatchStartsAllJobsPromptlyWithoutWaitingForEarlierJobs() async {
        let settings: MockSettingsGateway = configuredSettingsGateway()
        let storage: MockStorageGateway = MockStorageGateway()
        let delivery: MockDeliveryGateway = MockDeliveryGateway()
        let audio: MockTranscriptionGateway = MockTranscriptionGateway(
            supportedExtensions: FileType.audioExtensions
        )
        await audio.setProcessingDelay(.milliseconds(400))
        let ocr: MockTranscriptionGateway = MockTranscriptionGateway(
            supportedExtensions: FileType.pdfExtensions.union(FileType.imageExtensions)
        )
        let useCase: ProcessFileUseCase = ProcessFileUseCase(
            storage: storage,
            transcribers: [audio, ocr],
            delivery: delivery,
            settings: settings
        )
        let vm: JobListViewModel = JobListViewModel(
            useCase: useCase,
            settingsGateway: settings,
            outputFolderGateway: MockOutputFolderGateway(),
            shouldStartNetworkMonitoring: false
        )

        vm.processFiles([
            URL(filePath: "/tmp/first.mp3"),
            URL(filePath: "/tmp/second.mp3"),
            URL(filePath: "/tmp/third.mp3")
        ])

        let startedPromptly: Bool = await waitUntil(timeout: .milliseconds(200)) {
            let attemptCount: Int = await audio.recordedProcessAttemptCount()
            return vm.activeJobs.count == 3 && attemptCount == 3
        }

        #expect(startedPromptly)
    }

    @Test func removingActiveJobCancelsUnderlyingProcessingTask() async {
        let storage: MockStorageGateway = MockStorageGateway()
        let delivery: MockDeliveryGateway = MockDeliveryGateway()
        let settings: MockSettingsGateway = configuredSettingsGateway()
        let audio: MockTranscriptionGateway = MockTranscriptionGateway(
            supportedExtensions: FileType.audioExtensions
        )
        await audio.setProcessingDelay(.seconds(3))
        let ocr: MockTranscriptionGateway = MockTranscriptionGateway(
            supportedExtensions: FileType.pdfExtensions.union(FileType.imageExtensions)
        )

        let useCase: ProcessFileUseCase = ProcessFileUseCase(
            storage: storage,
            transcribers: [audio, ocr],
            delivery: delivery,
            settings: settings
        )
        let vm: JobListViewModel = JobListViewModel(
            useCase: useCase,
            settingsGateway: settings,
            outputFolderGateway: MockOutputFolderGateway(),
            shouldStartNetworkMonitoring: false
        )

        vm.processFiles([URL(filePath: "/tmp/slow.mp3")])
        let started: Bool = await waitUntil { vm.activeJobs.count == 1 }
        #expect(started)

        guard let jobID: UUID = vm.activeJobs.first?.id else {
            #expect(Bool(false))
            return
        }

        vm.removeJob(id: jobID)
        let removed: Bool = await waitUntil { vm.jobs.isEmpty }
        #expect(removed)

        // Give the cancelled task opportunity to finish cooperatively.
        for _ in 0..<50 {
            await Task.yield()
        }
        #expect(await delivery.recordedDeliveredResults().isEmpty)
        #expect(vm.jobs.isEmpty)
    }

    @Test func successfulProcessingPostsNotificationOnlyAfterCompletion() async {
        let savedFileURL: URL = URL(filePath: "/tmp/success.md")
        let delivery: MockDeliveryGateway = MockDeliveryGateway(savedFileURL: savedFileURL)
        let notificationGateway: MockNotificationGateway = MockNotificationGateway()
        let (vm, _, _, _, _, _) = makeViewModel(
            delivery: delivery,
            settings: configuredSettingsGateway(),
            notificationGateway: notificationGateway
        )

        #expect(await notificationGateway.recordedNotifications().isEmpty)

        vm.processFiles([URL(filePath: "/tmp/success.mp3")])

        let notified: Bool = await waitUntil(timeout: .seconds(2)) {
            !(await notificationGateway.recordedNotifications().isEmpty)
        }

        #expect(notified)
        let notifications: [(identifier: String, title: String, body: String)] = await notificationGateway.recordedNotifications()
        #expect(notifications.count == 1)
        #expect(UUID(uuidString: notifications[0].identifier) == vm.completedJobs.first?.id)
        #expect(notifications[0].title == "trnscrb")
        #expect(notifications[0].body == "success.mp3 saved to /tmp/success.md and copied to clipboard.")
    }

    @Test func successfulProcessingDoesNotReloadSettingsAfterPipelineCompletes() async {
        let settings: MockSettingsGateway = configuredSettingsGateway()
        let (vm, _, _, _, _, _) = makeViewModel(settings: settings)

        vm.processFiles([URL(filePath: "/tmp/no-extra-load.mp3")])

        let completed: Bool = await waitUntil(timeout: .seconds(2)) {
            vm.activeJobs.isEmpty && vm.completedJobs.count == 1
        }

        #expect(completed)
        #expect(await settings.recordedLoadSettingsCallCount() == 2)
    }

    @Test func successfulProcessingWithoutClipboardUsesSavedPathNotification() async {
        let savedFileURL: URL = URL(filePath: "/tmp/local-only.md")
        let delivery: MockDeliveryGateway = MockDeliveryGateway(savedFileURL: savedFileURL)
        let notificationGateway: MockNotificationGateway = MockNotificationGateway()
        let settings: MockSettingsGateway = MockSettingsGateway(
            settings: AppSettings(
                s3EndpointURL: "https://s3.example.com",
                s3AccessKey: "AKID",
                s3BucketName: "bucket",
                copyToClipboard: false
            ),
            secrets: [
                .mistralAPIKey: "mk-test",
                .s3SecretKey: "sk-test"
            ]
        )
        let (vm, _, _, _, _, _) = makeViewModel(
            delivery: delivery,
            settings: settings,
            notificationGateway: notificationGateway
        )

        vm.processFiles([URL(filePath: "/tmp/local-only.mp3")])

        let notified: Bool = await waitUntil(timeout: .seconds(2)) {
            !(await notificationGateway.recordedNotifications().isEmpty)
        }

        #expect(notified)
        let notifications: [(identifier: String, title: String, body: String)] = await notificationGateway.recordedNotifications()
        #expect(notifications[0].body == "local-only.mp3 saved to /tmp/local-only.md.")
    }

    @Test func successfulProcessingWithDeliveryWarningMarksCompletedJobAndWarnsUser() async {
        let savedFileURL: URL = URL(filePath: "/tmp/warned.md")
        let delivery: MockDeliveryGateway = MockDeliveryGateway(
            deliverWarnings: ["Saved markdown to the output folder, but copying to the clipboard failed."],
            savedFileURL: savedFileURL
        )
        let notificationGateway: MockNotificationGateway = MockNotificationGateway()
        let (vm, _, _, _, _, _) = makeViewModel(
            delivery: delivery,
            settings: configuredSettingsGateway(),
            notificationGateway: notificationGateway
        )

        vm.processFiles([URL(filePath: "/tmp/warned.mp3")])

        let completed: Bool = await waitUntil(timeout: .seconds(2)) {
            vm.activeJobs.isEmpty && vm.completedJobs.count == 1
        }
        #expect(completed)
        #expect(vm.completedJobs.first?.status == .completed)
        #expect(vm.completedJobs.first?.deliveryWarnings == [
            "Saved markdown to the output folder, but copying to the clipboard failed."
        ])
        #expect(vm.completedJobs.first?.savedFileURL == savedFileURL)

        let notified: Bool = await waitUntil(timeout: .seconds(2)) {
            !(await notificationGateway.recordedNotifications().isEmpty)
        }
        #expect(notified)
        let notifications: [(identifier: String, title: String, body: String)] = await notificationGateway.recordedNotifications()
        #expect(notifications[0].body == "warned.mp3 saved to /tmp/warned.md, but copying to the clipboard failed.")
    }

    @Test func successfulProcessingStoresRevealAndSourceMetadata() async {
        let sourceURL: URL = URL(string: "https://s3.example.com/presigned")!
        let savedFileURL: URL = URL(filePath: "/tmp/meeting.md")
        let storage: MockStorageGateway = MockStorageGateway(uploadResult: sourceURL)
        let delivery: MockDeliveryGateway = MockDeliveryGateway(savedFileURL: savedFileURL)
        let settings: MockSettingsGateway = configuredSettingsGateway()
        let (vm, _, _, _, _, _) = makeViewModel(
            storage: storage,
            delivery: delivery,
            settings: settings
        )

        vm.processFiles([URL(filePath: "/tmp/meeting.mp3")])

        let completed: Bool = await waitUntil(timeout: .seconds(2)) {
            vm.activeJobs.isEmpty && vm.completedJobs.count == 1
        }

        #expect(completed)
        #expect(vm.completedJobs.first?.savedFileURL == savedFileURL)
        #expect(vm.completedJobs.first?.presignedSourceURL == sourceURL)
    }

    @Test func copyToClipboardSetsTransientCopiedFeedback() async {
        let (vm, _, _, _, _, _) = makeViewModel(copyFeedbackDuration: .milliseconds(20))
        var job: Job = Job(fileType: .audio, fileURL: URL(filePath: "/tmp/copied.mp3"))
        job.startUpload()
        job.startProcessing()
        job.complete(markdown: "# Copied")
        vm.jobs = [job]

        vm.copyToClipboard(jobID: job.id)

        #expect(
            vm.copyFeedback == JobListViewModel.CopyFeedback(
                jobID: job.id,
                target: .markdown
            )
        )
        let cleared: Bool = await waitUntil(timeout: .seconds(1)) {
            vm.copyFeedback == nil
        }
        #expect(cleared)
    }

    @Test func copySourceURLToClipboardSetsTransientCopiedFeedback() async {
        let (vm, _, _, _, _, _) = makeViewModel(copyFeedbackDuration: .milliseconds(20))
        let sourceURL: URL = URL(string: "https://s3.example.com/transcript-source")!
        var job: Job = Job(fileType: .audio, fileURL: URL(filePath: "/tmp/copied-source.mp3"))
        job.startUpload()
        job.startProcessing()
        job.complete(markdown: "# Copied Source", presignedSourceURL: sourceURL)
        vm.jobs = [job]

        vm.copySourceURLToClipboard(jobID: job.id)

        #expect(
            vm.copyFeedback == JobListViewModel.CopyFeedback(
                jobID: job.id,
                target: .sourceURL
            )
        )
        let cleared: Bool = await waitUntil(timeout: .seconds(1)) {
            vm.copyFeedback == nil
        }
        #expect(cleared)
    }

    @Test func openConfiguredSaveFolderUsesPreparedOutputDirectory() async {
        let recorder: LockedOpenedFolderRecorder = LockedOpenedFolderRecorder()
        let preparedURL: URL = URL(filePath: "/tmp/prepared-output-folder")
        let outputFolderGateway: MockOutputFolderGateway = MockOutputFolderGateway(
            preparedURL: preparedURL
        )
        let settings: MockSettingsGateway = configuredSettingsGateway()
        let (vm, _, _, _, _, _) = makeViewModel(
            settings: settings,
            outputFolderGateway: outputFolderGateway,
            openFolder: { url in
                recorder.append(url)
            }
        )

        await vm.openConfiguredSaveFolder()

        #expect(outputFolderGateway.recordedPreparedPaths() == ["~/Documents/trnscrb/"])
        #expect(recorder.snapshot() == [preparedURL])
    }

    @Test func failedProcessingMarksJobAsFailedInsteadOfLeavingItActive() async {
        let storage: MockStorageGateway = MockStorageGateway()
        let delivery: MockDeliveryGateway = MockDeliveryGateway()
        let settings: MockSettingsGateway = configuredSettingsGateway()
        let audio: MockTranscriptionGateway = MockTranscriptionGateway(
            supportedExtensions: FileType.audioExtensions,
            processError: MistralError.requestFailed(statusCode: 422, body: "bad request")
        )
        let ocr: MockTranscriptionGateway = MockTranscriptionGateway(
            supportedExtensions: FileType.pdfExtensions.union(FileType.imageExtensions)
        )

        let useCase: ProcessFileUseCase = ProcessFileUseCase(
            storage: storage,
            transcribers: [audio, ocr],
            delivery: delivery,
            settings: settings
        )
        let vm: JobListViewModel = JobListViewModel(
            useCase: useCase,
            settingsGateway: settings,
            outputFolderGateway: MockOutputFolderGateway(),
            shouldStartNetworkMonitoring: false
        )

        vm.processFiles([URL(filePath: "/tmp/failure.mp3")])

        let failed: Bool = await waitUntil(timeout: .seconds(2)) {
            vm.activeJobs.isEmpty && vm.completedJobs.count == 1
        }

        #expect(failed)
        #expect(vm.selectedJobID == vm.completedJobs.first?.id)
        guard case .failed(let message)? = vm.completedJobs.first?.status else {
            #expect(Bool(false))
            return
        }
        #expect(message.contains("HTTP 422"))
        #expect(await delivery.recordedDeliveredResults().isEmpty)
    }
}
