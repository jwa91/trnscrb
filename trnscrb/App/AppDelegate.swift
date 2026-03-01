import AppKit
import SwiftUI

/// Application delegate and composition root.
///
/// Creates the `NSStatusItem` (menu bar icon), manages the `NSPopover`,
/// and wires all infrastructure dependencies. This is the only component
/// that knows about all layers — it creates concrete instances and injects
/// them into view models and use cases.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The menu bar status item showing the app icon.
    private var statusItem: NSStatusItem?
    /// The popover displayed when the status item is clicked.
    private var popover: NSPopover?
    /// Settings gateway for the lifetime of the app.
    private var settingsGateway: (any SettingsGateway)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Build infrastructure
        let keychainStore: KeychainStore = KeychainStore()
        let gateway: TOMLConfigManager = TOMLConfigManager(keychainStore: keychainStore)
        settingsGateway = gateway

        // Build presentation
        let settingsVM: SettingsViewModel = SettingsViewModel(gateway: gateway)

        // Setup popover
        let popover: NSPopover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 360)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(settingsViewModel: settingsVM)
        )
        self.popover = popover

        // Setup status item
        let statusItem: NSStatusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        if let button: NSStatusBarButton = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "doc.text",
                accessibilityDescription: "trnscrb"
            )
            button.action = #selector(togglePopover)
            button.target = self
        }
        self.statusItem = statusItem
    }

    /// Toggles the popover visibility when the menu bar icon is clicked.
    @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
