import Foundation

/// Persists settings, secrets, and launch-at-login as one rollbackable operation.
public struct SaveSettingsUseCase: Sendable {
    private let gateway: any SettingsGateway
    private let outputFolderGateway: any OutputFolderGateway
    private let launchAtLoginUseCase: ApplyLaunchAtLoginUseCase?

    public init(
        gateway: any SettingsGateway,
        outputFolderGateway: any OutputFolderGateway,
        launchAtLoginUseCase: ApplyLaunchAtLoginUseCase? = nil
    ) {
        self.gateway = gateway
        self.outputFolderGateway = outputFolderGateway
        self.launchAtLoginUseCase = launchAtLoginUseCase
    }

    public func save(
        settings: AppSettings,
        mistralAPIKey: String,
        s3SecretKey: String
    ) async throws {
        var normalizedSettings: AppSettings = try settings.validatedForPersistence()
        let normalizedMistralAPIKey: String = mistralAPIKey.trimmedCredentialValue
        let normalizedS3SecretKey: String = s3SecretKey.trimmedCredentialValue

        let preparedFolder: PreparedOutputFolder = try outputFolderGateway.prepareOutputFolder(
            settings: normalizedSettings
        )
        preparedFolder.stopAccessing()
        if let refreshedBookmarkBase64: String = preparedFolder.refreshedBookmarkBase64 {
            normalizedSettings.saveFolderBookmarkBase64 = refreshedBookmarkBase64
        }

        let snapshot: SettingsSnapshot = try await loadSnapshot()
        var didPersistSettings: Bool = false
        var didPersistMistralAPIKey: Bool = false
        var didPersistS3SecretKey: Bool = false
        var didAttemptLaunchAtLoginApply: Bool = false

        do {
            try await gateway.saveSettings(normalizedSettings)
            didPersistSettings = true
            try await persistSecret(normalizedMistralAPIKey, for: .mistralAPIKey)
            didPersistMistralAPIKey = true
            try await persistSecret(normalizedS3SecretKey, for: .s3SecretKey)
            didPersistS3SecretKey = true
            didAttemptLaunchAtLoginApply =
                launchAtLoginUseCase != nil
                && snapshot.settings.launchAtLogin != normalizedSettings.launchAtLogin
            if didAttemptLaunchAtLoginApply {
                try await launchAtLoginUseCase?.apply(enabled: normalizedSettings.launchAtLogin)
            }
        } catch {
            await rollback(
                to: snapshot,
                originalError: error,
                didPersistSettings: didPersistSettings,
                didPersistMistralAPIKey: didPersistMistralAPIKey,
                didPersistS3SecretKey: didPersistS3SecretKey,
                didAttemptLaunchAtLoginApply: didAttemptLaunchAtLoginApply
            )
            throw error
        }
    }

    public func saveSettingsOnly(_ settings: AppSettings) async throws {
        var normalizedSettings: AppSettings = try settings.validatedForPersistence()

        let preparedFolder: PreparedOutputFolder = try outputFolderGateway.prepareOutputFolder(
            settings: normalizedSettings
        )
        preparedFolder.stopAccessing()
        if let refreshedBookmarkBase64: String = preparedFolder.refreshedBookmarkBase64 {
            normalizedSettings.saveFolderBookmarkBase64 = refreshedBookmarkBase64
        }

        let snapshot: SettingsSnapshot = try await loadSnapshot()
        var didPersistSettings: Bool = false
        var didAttemptLaunchAtLoginApply: Bool = false

        do {
            try await gateway.saveSettings(normalizedSettings)
            didPersistSettings = true
            didAttemptLaunchAtLoginApply =
                launchAtLoginUseCase != nil
                && snapshot.settings.launchAtLogin != normalizedSettings.launchAtLogin
            if didAttemptLaunchAtLoginApply {
                try await launchAtLoginUseCase?.apply(enabled: normalizedSettings.launchAtLogin)
            }
        } catch {
            await rollback(
                to: snapshot,
                originalError: error,
                didPersistSettings: didPersistSettings,
                didPersistMistralAPIKey: false,
                didPersistS3SecretKey: false,
                didAttemptLaunchAtLoginApply: didAttemptLaunchAtLoginApply
            )
            throw error
        }
    }

    private func loadSnapshot() async throws -> SettingsSnapshot {
        let settings: AppSettings = try await gateway.loadSettings()
        let mistralAPIKey: String = try await gateway.getSecret(for: .mistralAPIKey) ?? ""
        let s3SecretKey: String = try await gateway.getSecret(for: .s3SecretKey) ?? ""
        return SettingsSnapshot(
            settings: settings,
            mistralAPIKey: mistralAPIKey,
            s3SecretKey: s3SecretKey
        )
    }

    private func persistSecret(_ value: String, for key: SecretKey) async throws {
        if value.isEmpty {
            try await gateway.removeSecret(for: key)
        } else {
            try await gateway.setSecret(value, for: key)
        }
    }

    private func rollback(
        to snapshot: SettingsSnapshot,
        originalError: any Error,
        didPersistSettings: Bool,
        didPersistMistralAPIKey: Bool,
        didPersistS3SecretKey: Bool,
        didAttemptLaunchAtLoginApply: Bool
    ) async {
        if didPersistSettings {
            do {
                try await gateway.saveSettings(snapshot.settings)
            } catch {
                logRollbackFailure(
                    step: "settings",
                    rollbackError: error,
                    originalError: originalError
                )
            }
        }
        if didPersistMistralAPIKey {
            do {
                try await persistSecret(snapshot.mistralAPIKey, for: .mistralAPIKey)
            } catch {
                logRollbackFailure(
                    step: "mistral API key",
                    rollbackError: error,
                    originalError: originalError
                )
            }
        }
        if didPersistS3SecretKey {
            do {
                try await persistSecret(snapshot.s3SecretKey, for: .s3SecretKey)
            } catch {
                logRollbackFailure(
                    step: "S3 secret key",
                    rollbackError: error,
                    originalError: originalError
                )
            }
        }
        if didAttemptLaunchAtLoginApply {
            do {
                try await launchAtLoginUseCase?.apply(enabled: snapshot.settings.launchAtLogin)
            } catch {
                logRollbackFailure(
                    step: "launch at login",
                    rollbackError: error,
                    originalError: originalError
                )
            }
        }
    }

    private func logRollbackFailure(
        step: String,
        rollbackError: any Error,
        originalError: any Error
    ) {
        AppLog.config.error(
            "Rollback step \(step, privacy: .public) failed after save error \(originalError.localizedDescription, privacy: .public): \(rollbackError.localizedDescription, privacy: .public)"
        )
    }
}

private struct SettingsSnapshot: Sendable {
    let settings: AppSettings
    let mistralAPIKey: String
    let s3SecretKey: String
}
