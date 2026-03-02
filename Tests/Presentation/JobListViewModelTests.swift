import Foundation
import Testing

@testable import trnscrb

@MainActor
struct JobListViewModelTests {
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
        delivery: MockDeliveryGateway = MockDeliveryGateway(),
        settings: MockSettingsGateway
    ) -> (JobListViewModel, MockStorageGateway, MockDeliveryGateway, MockSettingsGateway) {
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
            settingsGateway: settings
        )
        return (vm, storage, delivery, settings)
    }

    private func makeViewModel(
        storage: MockStorageGateway = MockStorageGateway(),
        delivery: MockDeliveryGateway = MockDeliveryGateway()
    ) -> (JobListViewModel, MockStorageGateway, MockDeliveryGateway, MockSettingsGateway) {
        makeViewModel(storage: storage, delivery: delivery, settings: configuredSettingsGateway())
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

    // MARK: - File validation

    @Test func rejectsUnsupportedFileType() async {
        let (vm, _, _, _) = makeViewModel()
        vm.processFiles([URL(filePath: "/tmp/file.xyz")])
        #expect(vm.jobs.isEmpty)
        #expect(vm.dropError == "Unsupported file type: .xyz")
    }

    @Test func createsJobForSupportedFile() async {
        let (vm, _, _, _) = makeViewModel()
        vm.processFiles([URL(filePath: "/tmp/test.mp3")])
        #expect(vm.jobs.count == 1)
        #expect(vm.jobs[0].fileType == .audio)
        #expect(vm.jobs[0].fileName == "test.mp3")
    }

    @Test func createsJobsForMultipleFiles() async {
        let (vm, _, _, _) = makeViewModel()
        vm.processFiles([
            URL(filePath: "/tmp/audio.mp3"),
            URL(filePath: "/tmp/doc.pdf"),
            URL(filePath: "/tmp/photo.png")
        ])
        #expect(vm.jobs.count == 3)
    }

    @Test func filtersUnsupportedFromMixedBatch() async {
        let (vm, _, _, _) = makeViewModel()
        vm.processFiles([
            URL(filePath: "/tmp/good.mp3"),
            URL(filePath: "/tmp/bad.xyz"),
            URL(filePath: "/tmp/good.pdf")
        ])
        #expect(vm.jobs.count == 2)
        #expect(vm.dropError == "Unsupported file type: .xyz")
    }

    // MARK: - Configuration checks

    @Test func setsConfigErrorWhenS3NotConfigured() async {
        let settings: MockSettingsGateway = MockSettingsGateway(
            secrets: [.mistralAPIKey: "mk-test"]
        )
        // s3EndpointURL is empty by default — not configured
        let (vm, _, _, _) = makeViewModel(settings: settings)

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
        let (vm, _, _, _) = makeViewModel(settings: settings)

        vm.processFiles([URL(filePath: "/tmp/test.mp3")])
        let completed: Bool = await waitUntil {
            vm.configurationError != nil && vm.jobs.isEmpty
        }

        #expect(completed)
        #expect(vm.configurationError != nil)
        #expect(vm.jobs.isEmpty)
    }

    // MARK: - Completed jobs history

    @Test func completedJobsListHasMaxTenItems() async {
        let (vm, _, _, _) = makeViewModel()

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

    // MARK: - Computed properties

    @Test func activeJobsFiltersCorrectly() async {
        let (vm, _, _, _) = makeViewModel()
        vm.processFiles([URL(filePath: "/tmp/test.mp3")])
        // Job should be active immediately after creation
        #expect(vm.activeJobs.count == 1)
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
        let vm: JobListViewModel = JobListViewModel(useCase: useCase, settingsGateway: settings)

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
}
