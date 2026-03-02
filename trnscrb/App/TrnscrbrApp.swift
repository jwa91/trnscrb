import SwiftUI

/// Main entry point for the trnscrb menu bar app.
///
/// The SwiftUI lifecycle manages the process. All real work is done
/// by `AppDelegate`, which is bridged via `@NSApplicationDelegateAdaptor`.
@main
struct TrnscrbrApp: App {
    /// Bridges to the AppKit AppDelegate which owns the NSStatusItem and NSPopover.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            // Settings are handled inside the popover, so disable the
            // app-level settings command/window entry point.
            CommandGroup(replacing: .appSettings) {}
        }
    }
}
