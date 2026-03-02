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
    public func deliver(result: TranscriptionResult) async throws -> DeliveryReport {
        let settings: AppSettings = try await settingsGateway.loadSettings()
        guard settings.hasEnabledOutputDestination else {
            // Never drop successful output on the floor; clipboard is the spec default.
            return try await clipboard.deliver(result: result)
        }

        var successfulDeliveries: Int = 0
        var firstError: (any Error)?
        var clipboardFailed: Bool = false
        var fileFailed: Bool = false

        if settings.copyToClipboard {
            do {
                _ = try await clipboard.deliver(result: result)
                successfulDeliveries += 1
            } catch {
                clipboardFailed = true
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if settings.saveToFolder {
            do {
                _ = try await file.deliver(result: result)
                successfulDeliveries += 1
            } catch {
                fileFailed = true
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if successfulDeliveries == 0, let firstError {
            throw firstError
        }

        var warnings: [String] = []
        if successfulDeliveries > 0 && settings.copyToClipboard && settings.saveToFolder {
            if clipboardFailed {
                warnings.append(
                    "Saved markdown to the output folder, but copying to the clipboard failed."
                )
            }
            if fileFailed {
                warnings.append(
                    "Copied markdown to the clipboard, but saving the file failed."
                )
            }
        }

        return DeliveryReport(warnings: warnings)
    }
}
