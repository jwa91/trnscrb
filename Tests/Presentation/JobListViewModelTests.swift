import Foundation
import Testing

@testable import trnscrb

@MainActor
struct JobListViewModelTests {
    private func makeViewModel(
        storage: MockStorageGateway = MockStorageGateway(),
        delivery: MockDeliveryGateway = MockDeliveryGateway(),
        settings: MockSettingsGateway = {
            let g: MockSettingsGateway = MockSettingsGateway()
            g.settings.s3EndpointURL = "https://s3.example.com"
            g.settings.s3AccessKey = "AKID"
            g.settings.s3BucketName = "bucket"
            g.secrets[.mistralAPIKey] = "mk-test"
            g.secrets[.s3SecretKey] = "sk-test"
            return g
        }()
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

    // MARK: - File validation

    @Test func rejectsUnsupportedFileType() async {
        let (vm, _, _, _) = makeViewModel()
        vm.processFiles([URL(filePath: "/tmp/file.xyz")])
        #expect(vm.jobs.isEmpty)
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
    }

    // MARK: - Configuration checks

    @Test func setsConfigErrorWhenS3NotConfigured() async {
        let settings: MockSettingsGateway = MockSettingsGateway()
        // s3EndpointURL is empty by default — not configured
        settings.secrets[.mistralAPIKey] = "mk-test"
        let (vm, _, _, _) = makeViewModel(settings: settings)

        vm.processFiles([URL(filePath: "/tmp/test.mp3")])
        // Allow async configuration check to complete
        try? await Task.sleep(for: .milliseconds(50))

        #expect(vm.configurationError != nil)
        #expect(vm.jobs.isEmpty)
    }

    @Test func setsConfigErrorWhenAPIKeyMissing() async {
        let settings: MockSettingsGateway = MockSettingsGateway()
        settings.settings.s3EndpointURL = "https://s3.example.com"
        settings.settings.s3AccessKey = "AKID"
        settings.settings.s3BucketName = "bucket"
        // No Mistral API key
        settings.secrets[.s3SecretKey] = "sk-test"
        let (vm, _, _, _) = makeViewModel(settings: settings)

        vm.processFiles([URL(filePath: "/tmp/test.mp3")])
        try? await Task.sleep(for: .milliseconds(50))

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
        // Allow processing to complete
        try? await Task.sleep(for: .milliseconds(200))

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
}
