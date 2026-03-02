import Foundation

/// Deletes expired objects from S3 storage after the retention period.
///
/// Runs periodically in the background. Queries `StorageGateway` for
/// objects older than the configured retention hours and deletes them.
public final class CleanupRetentionUseCase: Sendable {
    /// Object storage to query and clean up.
    private let storage: any StorageGateway
    /// Settings for retention period configuration.
    private let settings: any SettingsGateway

    /// Creates the use case with injected dependencies.
    public init(
        storage: any StorageGateway,
        settings: any SettingsGateway
    ) {
        self.storage = storage
        self.settings = settings
    }

    /// Finds and deletes all expired S3 objects.
    public func execute() async throws {
        let appSettings: AppSettings = try await settings.loadSettings()
        guard appSettings.fileRetentionHours > 0 else {
            return
        }

        let cutoff: Date = Date().addingTimeInterval(-Double(appSettings.fileRetentionHours) * 3600)
        let keys: [String] = try await storage.listCreatedBefore(cutoff)

        var firstError: (any Error)?
        for key in keys {
            do {
                try await storage.delete(key: key)
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if let firstError {
            throw firstError
        }
    }
}
