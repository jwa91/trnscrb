import Foundation
import Testing

@testable import trnscrb

private actor CleanupStorageSpy: StorageGateway {
    var keysToReturn: [String]
    var deletedKeys: [String] = []
    var listCallCount: Int = 0
    var deleteErrorKeys: Set<String> = []

    init(keysToReturn: [String]) {
        self.keysToReturn = keysToReturn
    }

    func upload(
        fileURL _: URL,
        key _: String,
        onProgress _: (@Sendable (Double) -> Void)?
    ) async throws -> URL {
        URL(string: "https://example.com")!
    }

    func delete(key: String) async throws {
        deletedKeys.append(key)
        if deleteErrorKeys.contains(key) {
            throw S3Error.requestFailed(statusCode: 500, body: "Delete failed")
        }
    }

    func listCreatedBefore(_ cutoff: Date) async throws -> [String] {
        _ = cutoff
        listCallCount += 1
        return keysToReturn
    }

    func addDeleteError(for key: String) {
        deleteErrorKeys.insert(key)
    }

    func recordedDeletedKeys() -> [String] {
        deletedKeys
    }

    func recordedListCallCount() -> Int {
        listCallCount
    }
}

private actor CleanupSettingsSpy: SettingsGateway {
    var settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func loadSettings() async throws -> AppSettings {
        settings
    }

    func saveSettings(_ settings: AppSettings) async throws {
        self.settings = settings
    }

    func getSecret(for key: SecretKey) async throws -> String? {
        _ = key
        return nil
    }

    func setSecret(_ value: String, for key: SecretKey) async throws {
        _ = value
        _ = key
    }

    func removeSecret(for key: SecretKey) async throws {
        _ = key
    }
}

struct CleanupRetentionUseCaseTests {
    @Test func deletesAllExpiredKeys() async throws {
        let storage: CleanupStorageSpy = CleanupStorageSpy(
            keysToReturn: ["trnscrb/a.mp3", "trnscrb/b.pdf"]
        )
        let settings: CleanupSettingsSpy = CleanupSettingsSpy(
            settings: AppSettings(fileRetentionHours: 24)
        )
        let useCase: CleanupRetentionUseCase = CleanupRetentionUseCase(
            storage: storage,
            settings: settings
        )

        try await useCase.execute()

        #expect(await storage.recordedListCallCount() == 1)
        #expect(await storage.recordedDeletedKeys() == ["trnscrb/a.mp3", "trnscrb/b.pdf"])
    }

    @Test func skipsCleanupWhenRetentionHoursIsNonPositive() async throws {
        let storage: CleanupStorageSpy = CleanupStorageSpy(keysToReturn: ["trnscrb/a.mp3"])
        let settings: CleanupSettingsSpy = CleanupSettingsSpy(
            settings: AppSettings(fileRetentionHours: 0)
        )
        let useCase: CleanupRetentionUseCase = CleanupRetentionUseCase(
            storage: storage,
            settings: settings
        )

        try await useCase.execute()

        #expect(await storage.recordedListCallCount() == 0)
        #expect(await storage.recordedDeletedKeys().isEmpty)
    }

    @Test func continuesDeletingAndThrowsFirstDeleteError() async {
        let storage: CleanupStorageSpy = CleanupStorageSpy(
            keysToReturn: ["trnscrb/a.mp3", "trnscrb/b.pdf"]
        )
        await storage.addDeleteError(for: "trnscrb/a.mp3")
        let settings: CleanupSettingsSpy = CleanupSettingsSpy(
            settings: AppSettings(fileRetentionHours: 24)
        )
        let useCase: CleanupRetentionUseCase = CleanupRetentionUseCase(
            storage: storage,
            settings: settings
        )

        await #expect(throws: S3Error.self) {
            try await useCase.execute()
        }
        #expect(await storage.recordedDeletedKeys() == ["trnscrb/a.mp3", "trnscrb/b.pdf"])
    }
}
