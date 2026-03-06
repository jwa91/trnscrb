import Foundation
import Testing

@testable import trnscrb

@MainActor
struct SettingsViewModelTests {
    private func makeViewModel(
        settings: AppSettings = AppSettings(),
        secrets: [SecretKey: String] = [:]
    ) -> (
        SettingsViewModel,
        MockSettingsGateway,
        MockConnectivityGateway,
        MockLaunchAtLoginGateway,
        MockOutputFolderGateway
    ) {
        let gateway: MockSettingsGateway = MockSettingsGateway(
            settings: settings,
            secrets: secrets
        )
        let connectivityGateway: MockConnectivityGateway = MockConnectivityGateway()
        let launchAtLoginGateway: MockLaunchAtLoginGateway = MockLaunchAtLoginGateway()
        let outputFolderGateway: MockOutputFolderGateway = MockOutputFolderGateway()
        let connectivityUseCase: TestConnectivityUseCase = TestConnectivityUseCase(
            gateway: connectivityGateway
        )
        let saveSettingsUseCase: SaveSettingsUseCase = SaveSettingsUseCase(
            gateway: gateway,
            outputFolderGateway: outputFolderGateway,
            launchAtLoginUseCase: ApplyLaunchAtLoginUseCase(gateway: launchAtLoginGateway)
        )
        let vm: SettingsViewModel = SettingsViewModel(
            gateway: gateway,
            connectivityUseCase: connectivityUseCase,
            outputFolderGateway: outputFolderGateway,
            saveSettingsUseCase: saveSettingsUseCase
        )
        return (vm, gateway, connectivityGateway, launchAtLoginGateway, outputFolderGateway)
    }

    // MARK: - Loading

    @Test func loadPopulatesSettingsFromGateway() async {
        let customSettings: AppSettings = AppSettings(
            s3EndpointURL: "https://test.com",
            s3BucketName: "bucket",
            outputFileNamePrefix: "notes-",
            outputFileNameTemplate: "{prefix}{originalFilename}",
            appleAudioLocaleIdentifier: "nl-NL"
        )
        let (vm, _, _, _, _) = makeViewModel(settings: customSettings)
        await vm.load()
        #expect(vm.settings.s3EndpointURL == "https://test.com")
        #expect(vm.settings.s3BucketName == "bucket")
        #expect(vm.settings.outputFileNamePrefix == "notes-")
        #expect(vm.settings.outputFileNameTemplate == "{prefix}{originalFilename}")
        #expect(vm.settings.appleAudioLocaleIdentifier == "nl-NL")
    }

    @Test func loadPopulatesProviderModesFromGateway() async {
        let customSettings: AppSettings = AppSettings(
            audioProviderMode: .localApple,
            pdfProviderMode: .mistral,
            imageProviderMode: .localApple
        )
        let (vm, _, _, _, _) = makeViewModel(settings: customSettings)

        await vm.load()

        #expect(vm.settings.audioProviderMode == .localApple)
        #expect(vm.settings.pdfProviderMode == .mistral)
        #expect(vm.settings.imageProviderMode == .localApple)
    }

    @Test func loadPopulatesSecretsFromGateway() async {
        let secrets: [SecretKey: String] = [
            .mistralAPIKey: "mk-123",
            .s3SecretKey: "sk-456"
        ]
        let (vm, _, _, _, _) = makeViewModel(secrets: secrets)
        await vm.load()
        #expect(vm.mistralAPIKey == "mk-123")
        #expect(vm.s3SecretKey == "sk-456")
    }

    @Test func loadWithNoSecretsLeavesEmptyStrings() async {
        let (vm, _, _, _, _) = makeViewModel()
        await vm.load()
        #expect(vm.mistralAPIKey == "")
        #expect(vm.s3SecretKey == "")
    }

    // MARK: - Saving

    @Test func savePersistsSettingsToGateway() async {
        let (vm, gateway, _, _, _) = makeViewModel()
        vm.settings.s3EndpointURL = "https://saved.com"
        vm.settings.s3BucketName = "saved-bucket"
        vm.settings.outputFileNamePrefix = "notes-"
        vm.settings.outputFileNameTemplate = "{prefix}{fileType}"
        vm.settings.appleAudioLocaleIdentifier = "nl-NL"
        let didSave: Bool = await vm.save()
        #expect(didSave)
        let savedSettings: AppSettings = await gateway.snapshotSettings()
        #expect(savedSettings.s3EndpointURL == "https://saved.com")
        #expect(savedSettings.s3BucketName == "saved-bucket")
        #expect(savedSettings.outputFileNamePrefix == "notes-")
        #expect(savedSettings.outputFileNameTemplate == "{prefix}{fileType}")
        #expect(savedSettings.appleAudioLocaleIdentifier == "nl-NL")
    }

    @Test func savePersistsProviderModesToGateway() async {
        let (vm, gateway, _, _, _) = makeViewModel()
        vm.settings.audioProviderMode = .localApple
        vm.settings.pdfProviderMode = .mistral
        vm.settings.imageProviderMode = .localApple

        let didSave: Bool = await vm.save()
        let savedSettings: AppSettings = await gateway.snapshotSettings()

        #expect(didSave)
        #expect(savedSettings.audioProviderMode == .localApple)
        #expect(savedSettings.pdfProviderMode == .mistral)
        #expect(savedSettings.imageProviderMode == .localApple)
    }

    @Test func savePersistsSecretsToKeychain() async {
        let (vm, gateway, _, _, _) = makeViewModel()
        vm.mistralAPIKey = "new-mk"
        vm.s3SecretKey = "new-sk"
        await vm.save()
        let secrets: [SecretKey: String] = await gateway.snapshotSecrets()
        #expect(secrets[.mistralAPIKey] == "new-mk")
        #expect(secrets[.s3SecretKey] == "new-sk")
    }

    @Test func saveRemovesEmptySecrets() async {
        let secrets: [SecretKey: String] = [
            .mistralAPIKey: "existing",
            .s3SecretKey: "existing"
        ]
        let (vm, gateway, _, _, _) = makeViewModel(secrets: secrets)
        await vm.load()
        vm.mistralAPIKey = ""
        vm.s3SecretKey = ""
        await vm.save()
        let savedSecrets: [SecretKey: String] = await gateway.snapshotSecrets()
        #expect(savedSecrets[.mistralAPIKey] == nil)
        #expect(savedSecrets[.s3SecretKey] == nil)
    }

    // MARK: - Round-trip

    @Test func loadThenSaveRoundTrip() async {
        let original: AppSettings = AppSettings(
            s3EndpointURL: "https://rt.com",
            copyToClipboard: false,
            fileRetentionHours: 48
        )
        let (vm, gateway, _, _, _) = makeViewModel(
            settings: original,
            secrets: [.mistralAPIKey: "rt-key"]
        )
        await vm.load()
        await vm.save()
        #expect(await gateway.snapshotSettings() == original)
        #expect(await gateway.snapshotSecrets()[.mistralAPIKey] == "rt-key")
    }

    @Test func saveRejectsBlankSaveFolder() async {
        let (vm, gateway, _, launchAtLoginGateway, outputFolderGateway) = makeViewModel()
        vm.settings.saveFolderPath = "   "
        outputFolderGateway.setError(OutputFolderError.missingPath)

        let didSave: Bool = await vm.save()

        #expect(!didSave)
        #expect(await gateway.snapshotSettings() == AppSettings())
        #expect(await launchAtLoginGateway.recordedCallCount() == 0)
    }

    @Test func saveAllowsClipboardDisabled() async {
        let tempDir: URL = FileManager.default.temporaryDirectory
            .appending(path: "trnscrb-settings-vm-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let (vm, gateway, _, _, outputFolderGateway) = makeViewModel()
        vm.settings.copyToClipboard = false
        vm.settings.saveFolderPath = tempDir.path()
        outputFolderGateway.setPreparedURL(tempDir)

        let didSave: Bool = await vm.save()

        #expect(didSave)
        #expect((await gateway.snapshotSettings()).copyToClipboard == false)
        #expect((await gateway.snapshotSettings()).saveFolderPath == tempDir.path())
    }

    // MARK: - Connectivity testing

    @Test func testS3CallsConnectivityUseCaseOnSuccess() async {
        let (vm, _, connectivityGateway, _, _) = makeViewModel()
        vm.settings.s3EndpointURL = "https://s3.example.com"
        vm.settings.s3AccessKey = "AKID"
        vm.settings.s3BucketName = "bucket"
        vm.s3SecretKey = "secret"

        await vm.testS3()

        #expect(vm.s3TestResult == .success)
        #expect(await connectivityGateway.recordedS3CallCount() == 1)
    }

    @Test func testS3DoesNotCallConnectivityWhenRequiredFieldsMissing() async {
        let (vm, _, connectivityGateway, _, _) = makeViewModel()
        vm.settings.s3EndpointURL = ""
        vm.settings.s3AccessKey = "AKID"
        vm.settings.s3BucketName = "bucket"
        vm.s3SecretKey = "secret"

        await vm.testS3()

        #expect(await connectivityGateway.recordedS3CallCount() == 0)
        #expect(vm.s3TestResult == .failure("Fill in all S3 fields first"))
    }

    @Test func testMistralSurfacesConnectivityFailure() async {
        let (vm, _, connectivityGateway, _, _) = makeViewModel()
        vm.mistralAPIKey = "mk-invalid"
        await connectivityGateway.setMistralError(ConnectivityError.invalidAPIKey)

        await vm.testMistral()

        #expect(await connectivityGateway.recordedMistralCallCount() == 1)
        #expect(vm.mistralTestResult == .failure("Invalid API key"))
    }

    @Test func testMistralReportsSuccess() async {
        let (vm, _, connectivityGateway, _, _) = makeViewModel()
        vm.mistralAPIKey = "  mk-valid  "

        await vm.testMistral()

        #expect(await connectivityGateway.recordedMistralCallCount() == 1)
        #expect(vm.mistralAPIKey == "mk-valid")
        #expect(vm.mistralTestResult == .success)
    }

}
