import Foundation
import Testing

@testable import trnscrb

private enum SaveSettingsTestError: Error, Sendable, Equatable {
    case setSecretFailed
    case saveSettingsFailed
    case launchAtLoginFailed
}

private actor RecordingSettingsGateway: SettingsGateway {
    private var settings: AppSettings
    private var secrets: [SecretKey: String]
    private var setSecretErrors: [SecretKey: any Error & Sendable] = [:]
    private var saveSettingsErrorsByCall: [Int: any Error & Sendable] = [:]
    private var saveSettingsCallCount: Int = 0

    init(
        settings: AppSettings = AppSettings(),
        secrets: [SecretKey: String] = [:]
    ) {
        self.settings = settings
        self.secrets = secrets
    }

    func snapshotSettings() -> AppSettings {
        settings
    }

    func snapshotSecrets() -> [SecretKey: String] {
        secrets
    }

    func setSetSecretError(_ error: (any Error & Sendable)?, for key: SecretKey) {
        setSecretErrors[key] = error
    }

    func setSaveSettingsError(_ error: (any Error & Sendable)?, onCall call: Int) {
        saveSettingsErrorsByCall[call] = error
    }

    func loadSettings() async throws -> AppSettings {
        settings
    }

    func saveSettings(_ newSettings: AppSettings) async throws {
        saveSettingsCallCount += 1
        if let error = saveSettingsErrorsByCall[saveSettingsCallCount] {
            throw error
        }
        settings = newSettings
    }

    func getSecret(for key: SecretKey) async throws -> String? {
        secrets[key]
    }

    func setSecret(_ value: String, for key: SecretKey) async throws {
        if let error = setSecretErrors[key] {
            throw error
        }
        secrets[key] = value
    }

    func removeSecret(for key: SecretKey) async throws {
        secrets[key] = nil
    }
}

private actor FailingOnceLaunchAtLoginGateway: LaunchAtLoginGateway {
    private var shouldFail: Bool
    private var appliedValues: [Bool] = []

    init(shouldFail: Bool = true) {
        self.shouldFail = shouldFail
    }

    func recordedAppliedValues() -> [Bool] {
        appliedValues
    }

    func apply(enabled: Bool) async throws {
        appliedValues.append(enabled)
        if shouldFail {
            shouldFail = false
            throw SaveSettingsTestError.launchAtLoginFailed
        }
    }
}

struct SaveSettingsUseCaseTests {
    @Test func saveRejectsBlankSaveFolder() async {
        let gateway: RecordingSettingsGateway = RecordingSettingsGateway()
        let launchGateway: MockLaunchAtLoginGateway = MockLaunchAtLoginGateway()
        let outputFolderGateway: MockOutputFolderGateway = MockOutputFolderGateway()
        outputFolderGateway.setError(OutputFolderError.missingPath)
        let useCase: SaveSettingsUseCase = SaveSettingsUseCase(
            gateway: gateway,
            outputFolderGateway: outputFolderGateway,
            launchAtLoginUseCase: ApplyLaunchAtLoginUseCase(gateway: launchGateway)
        )

        let invalidSettings: AppSettings = AppSettings(
            saveFolderPath: "   "
        )

        await #expect(throws: Error.self) {
            try await useCase.save(
                settings: invalidSettings,
                mistralAPIKey: "mk-test",
                s3SecretKey: "sk-test"
            )
        }
    }

    @Test func saveAllowsClipboardDisabledWhenFolderIsConfigured() async throws {
        let gateway: RecordingSettingsGateway = RecordingSettingsGateway()
        let outputFolderGateway: MockOutputFolderGateway = MockOutputFolderGateway(
            preparedURL: URL(filePath: "/tmp/trnscrb-output")
        )
        let useCase: SaveSettingsUseCase = SaveSettingsUseCase(
            gateway: gateway,
            outputFolderGateway: outputFolderGateway
        )

        let settings: AppSettings = AppSettings(
            saveFolderPath: "/tmp/trnscrb-output",
            copyToClipboard: false
        )

        try await useCase.save(
            settings: settings,
            mistralAPIKey: "mk-test",
            s3SecretKey: "sk-test"
        )

        #expect((await gateway.snapshotSettings()).copyToClipboard == false)
        #expect((await gateway.snapshotSettings()).saveFolderPath == "/tmp/trnscrb-output")
        #expect(outputFolderGateway.recordedPreparedPaths() == ["/tmp/trnscrb-output"])
    }

    @Test func saveSettingsOnlyPersistsRefreshedOutputFolderBookmark() async throws {
        let gateway: RecordingSettingsGateway = RecordingSettingsGateway()
        let outputFolderGateway: MockOutputFolderGateway = MockOutputFolderGateway(
            preparedURL: URL(filePath: "/tmp/trnscrb-output")
        )
        outputFolderGateway.setRefreshedBookmarkBase64("new-bookmark")
        let useCase: SaveSettingsUseCase = SaveSettingsUseCase(
            gateway: gateway,
            outputFolderGateway: outputFolderGateway
        )

        try await useCase.saveSettingsOnly(
            AppSettings(
                saveFolderPath: "/tmp/trnscrb-output",
                saveFolderBookmarkBase64: "old-bookmark"
            )
        )

        #expect((await gateway.snapshotSettings()).saveFolderBookmarkBase64 == "new-bookmark")
        #expect(outputFolderGateway.recordedStopAccessCount() == 1)
    }

    @Test func saveDoesNotApplyLaunchAtLoginWhenValueIsUnchanged() async throws {
        let originalSettings: AppSettings = AppSettings(
            s3EndpointURL: "https://old.example.com",
            s3AccessKey: "OLDKEY",
            s3BucketName: "old-bucket",
            saveFolderPath: "/tmp/original-output",
            copyToClipboard: true,
            launchAtLogin: false
        )
        let gateway: RecordingSettingsGateway = RecordingSettingsGateway(
            settings: originalSettings,
            secrets: [
                .mistralAPIKey: "old-mistral",
                .s3SecretKey: "old-secret"
            ]
        )
        let launchGateway: MockLaunchAtLoginGateway = MockLaunchAtLoginGateway()
        let outputFolderGateway: MockOutputFolderGateway = MockOutputFolderGateway()
        let useCase: SaveSettingsUseCase = SaveSettingsUseCase(
            gateway: gateway,
            outputFolderGateway: outputFolderGateway,
            launchAtLoginUseCase: ApplyLaunchAtLoginUseCase(gateway: launchGateway)
        )

        try await useCase.save(
            settings: originalSettings,
            mistralAPIKey: "new-mistral",
            s3SecretKey: "new-secret"
        )

        #expect(await launchGateway.recordedCallCount() == 0)
        let secrets: [SecretKey: String] = await gateway.snapshotSecrets()
        #expect(secrets[.mistralAPIKey] == "new-mistral")
        #expect(secrets[.s3SecretKey] == "new-secret")
    }

    @Test func saveRollsBackPersistedStateWhenSecretWriteFails() async {
        let originalSettings: AppSettings = AppSettings(
            s3EndpointURL: "https://old.example.com",
            s3AccessKey: "OLDKEY",
            s3BucketName: "old-bucket",
            saveFolderPath: "/tmp/original-output",
            copyToClipboard: true
        )
        let gateway: RecordingSettingsGateway = RecordingSettingsGateway(
            settings: originalSettings,
            secrets: [
                .mistralAPIKey: "old-mistral",
                .s3SecretKey: "old-secret"
            ]
        )
        await gateway.setSetSecretError(SaveSettingsTestError.setSecretFailed, for: .s3SecretKey)
        let launchGateway: MockLaunchAtLoginGateway = MockLaunchAtLoginGateway()
        let outputFolderGateway: MockOutputFolderGateway = MockOutputFolderGateway()
        let useCase: SaveSettingsUseCase = SaveSettingsUseCase(
            gateway: gateway,
            outputFolderGateway: outputFolderGateway,
            launchAtLoginUseCase: ApplyLaunchAtLoginUseCase(gateway: launchGateway)
        )

        let newSettings: AppSettings = AppSettings(
            s3EndpointURL: "https://new.example.com",
            s3AccessKey: "NEWKEY",
            s3BucketName: "new-bucket",
            saveFolderPath: "/tmp/new-output",
            copyToClipboard: true,
            launchAtLogin: true
        )

        await #expect(throws: SaveSettingsTestError.self) {
            try await useCase.save(
                settings: newSettings,
                mistralAPIKey: "new-mistral",
                s3SecretKey: "new-secret"
            )
        }

        #expect(await gateway.snapshotSettings() == originalSettings)
        let secrets: [SecretKey: String] = await gateway.snapshotSecrets()
        #expect(secrets[.mistralAPIKey] == "old-mistral")
        #expect(secrets[.s3SecretKey] == "old-secret")
        #expect(await launchGateway.recordedAppliedValues().isEmpty)
    }

    @Test func saveRollsBackWhenLaunchAtLoginApplyFails() async {
        let originalSettings: AppSettings = AppSettings(
            s3EndpointURL: "https://old.example.com",
            s3AccessKey: "OLDKEY",
            s3BucketName: "old-bucket",
            saveFolderPath: "/tmp/original-output",
            copyToClipboard: true,
            launchAtLogin: false
        )
        let gateway: RecordingSettingsGateway = RecordingSettingsGateway(
            settings: originalSettings,
            secrets: [
                .mistralAPIKey: "old-mistral",
                .s3SecretKey: "old-secret"
            ]
        )
        let launchGateway: FailingOnceLaunchAtLoginGateway = FailingOnceLaunchAtLoginGateway()
        let outputFolderGateway: MockOutputFolderGateway = MockOutputFolderGateway()
        let useCase: SaveSettingsUseCase = SaveSettingsUseCase(
            gateway: gateway,
            outputFolderGateway: outputFolderGateway,
            launchAtLoginUseCase: ApplyLaunchAtLoginUseCase(gateway: launchGateway)
        )

        let newSettings: AppSettings = AppSettings(
            s3EndpointURL: "https://new.example.com",
            s3AccessKey: "NEWKEY",
            s3BucketName: "new-bucket",
            saveFolderPath: "/tmp/new-output",
            copyToClipboard: true,
            launchAtLogin: true
        )

        await #expect(throws: SaveSettingsTestError.self) {
            try await useCase.save(
                settings: newSettings,
                mistralAPIKey: "new-mistral",
                s3SecretKey: "new-secret"
            )
        }

        #expect(await gateway.snapshotSettings() == originalSettings)
        let secrets: [SecretKey: String] = await gateway.snapshotSecrets()
        #expect(secrets[.mistralAPIKey] == "old-mistral")
        #expect(secrets[.s3SecretKey] == "old-secret")
        #expect(await launchGateway.recordedAppliedValues() == [true, false])
    }

    @Test func saveThrowsOriginalErrorWhenRollbackSettingsRestoreFails() async {
        let originalSettings: AppSettings = AppSettings(
            s3EndpointURL: "https://old.example.com",
            s3AccessKey: "OLDKEY",
            s3BucketName: "old-bucket",
            saveFolderPath: "/tmp/original-output",
            copyToClipboard: true
        )
        let gateway: RecordingSettingsGateway = RecordingSettingsGateway(
            settings: originalSettings,
            secrets: [
                .mistralAPIKey: "old-mistral",
                .s3SecretKey: "old-secret"
            ]
        )
        await gateway.setSetSecretError(SaveSettingsTestError.setSecretFailed, for: .s3SecretKey)
        await gateway.setSaveSettingsError(SaveSettingsTestError.saveSettingsFailed, onCall: 2)
        let outputFolderGateway: MockOutputFolderGateway = MockOutputFolderGateway()
        let useCase: SaveSettingsUseCase = SaveSettingsUseCase(
            gateway: gateway,
            outputFolderGateway: outputFolderGateway
        )

        let newSettings: AppSettings = AppSettings(
            s3EndpointURL: "https://new.example.com",
            s3AccessKey: "NEWKEY",
            s3BucketName: "new-bucket",
            saveFolderPath: "/tmp/new-output",
            copyToClipboard: true
        )

        do {
            try await useCase.save(
                settings: newSettings,
                mistralAPIKey: "new-mistral",
                s3SecretKey: "new-secret"
            )
            #expect(Bool(false))
        } catch let error as SaveSettingsTestError {
            #expect(error == .setSecretFailed)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(await gateway.snapshotSettings() == newSettings)
        let secrets: [SecretKey: String] = await gateway.snapshotSecrets()
        #expect(secrets[.mistralAPIKey] == "old-mistral")
        #expect(secrets[.s3SecretKey] == "old-secret")
    }
}
