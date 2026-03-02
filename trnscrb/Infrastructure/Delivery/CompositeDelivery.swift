import Foundation

/// Routes delivery to clipboard and/or file based on current settings.
///
/// Each delivery target is an independent `DeliveryGateway`. Settings are checked
/// at delivery time so toggling a mode takes effect immediately.
public struct CompositeDelivery: DeliveryGateway {
    /// Clipboard delivery handler.
    private let clipboard: any DeliveryGateway
    /// File-save delivery handler.
    private let file: any DeliveryGateway
    /// Reads settings to determine which modes are active.
    private let settingsGateway: any SettingsGateway

    /// Creates a composite delivery.
    /// - Parameters:
    ///   - clipboard: Delivery handler for clipboard output.
    ///   - file: Delivery handler for file-save output.
    ///   - settingsGateway: Provides current output mode settings.
    public init(
        clipboard: any DeliveryGateway,
        file: any DeliveryGateway,
        settingsGateway: any SettingsGateway
    ) {
        self.clipboard = clipboard
        self.file = file
        self.settingsGateway = settingsGateway
    }

    /// Delivers the result to all enabled output modes.
    public func deliver(result: TranscriptionResult) async throws {
        let settings: AppSettings = try await settingsGateway.loadSettings()
        if settings.copyToClipboard {
            try await clipboard.deliver(result: result)
        }
        if settings.saveToFolder {
            try await file.deliver(result: result)
        }
    }
}
