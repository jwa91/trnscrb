import AppKit
import SwiftUI

/// Main entry point for the trnscrb menu bar app.
///
/// The SwiftUI lifecycle manages the process. All real work is done
/// by `AppDelegate`, which is bridged via `@NSApplicationDelegateAdaptor`.
@main
struct TrnscrbrApp: App {
    /// Bridges to the AppKit AppDelegate which owns the NSStatusItem and menu panel host.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Files…") {
                    Task { @MainActor in
                        appDelegate.addFilesFromCommand()
                    }
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    Task { @MainActor in
                        appDelegate.showSettingsFromCommand()
                    }
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(replacing: .appTermination) {
                Button("Quit trnscrb") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}
