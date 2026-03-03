import Foundation
import Testing

@testable import trnscrb

private enum SaveSettingsTestError: Error, Sendable {
    case setSecretFailed
    case launchAtLoginFailed
}

private actor RecordingSettingsGateway: SettingsGateway {
    private var settings: AppSettings
    private var secrets: [SecretKey: String]
    private var setSecretErrors: [SecretKey: any Error & Sendable] = [:]

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

    func loadSettings() async throws -> AppSettings {
        settings
    }

    func saveSettings(_ newSettings: AppSettings) async throws {
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
    @Test func saveRejectsWhenAllOutputsAreDisabled() async {
        let gateway: RecordingSettingsGateway = RecordingSettingsGateway()
        let launchGateway: MockLaunchAtLoginGateway = MockLaunchAtLoginGateway()
        let useCase: SaveSettingsUseCase = SaveSettingsUseCase(
            gateway: gateway,
            launchAtLoginUseCase: ApplyLaunchAtLoginUseCase(gateway: launchGateway)
        )

        let invalidSettings: AppSettings = AppSettings(
            copyToClipboard: false,
            saveToFolder: false
        )

        await #expect(throws: SettingsSaveError.self) {
            try await useCase.save(
                settings: invalidSettings,
                mistralAPIKey: "mk-test",
                s3SecretKey: "sk-test"
            )
        }
    }

    @Test func saveDoesNotApplyLaunchAtLoginWhenValueIsUnchanged() async throws {
        let originalSettings: AppSettings = AppSettings(
            s3EndpointURL: "https://old.example.com",
            s3AccessKey: "OLDKEY",
            s3BucketName: "old-bucket",
            copyToClipboard: true,
            saveToFolder: true,
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
        let useCase: SaveSettingsUseCase = SaveSettingsUseCase(
            gateway: gateway,
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
            copyToClipboard: true,
            saveToFolder: false
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
        let useCase: SaveSettingsUseCase = SaveSettingsUseCase(
            gateway: gateway,
            launchAtLoginUseCase: ApplyLaunchAtLoginUseCase(gateway: launchGateway)
        )

        let newSettings: AppSettings = AppSettings(
            s3EndpointURL: "https://new.example.com",
            s3AccessKey: "NEWKEY",
            s3BucketName: "new-bucket",
            copyToClipboard: true,
            saveToFolder: true,
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
            copyToClipboard: true,
            saveToFolder: false,
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
        let useCase: SaveSettingsUseCase = SaveSettingsUseCase(
            gateway: gateway,
            launchAtLoginUseCase: ApplyLaunchAtLoginUseCase(gateway: launchGateway)
        )

        let newSettings: AppSettings = AppSettings(
            s3EndpointURL: "https://new.example.com",
            s3AccessKey: "NEWKEY",
            s3BucketName: "new-bucket",
            copyToClipboard: true,
            saveToFolder: true,
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
}
