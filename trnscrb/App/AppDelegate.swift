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
    /// Monitors clicks outside the popover to dismiss it.
    private var eventMonitor: Any?

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
        popover.delegate = self
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
            closePopover()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            button.highlight(true)
            startEventMonitor()
        }
    }

    /// Closes the popover and removes the event monitor.
    private func closePopover() {
        popover?.performClose(nil)
    }

    /// Installs a global event monitor that closes the popover on outside clicks.
    private func startEventMonitor() {
        stopEventMonitor()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.closePopover()
        }
    }

    /// Removes the global event monitor.
    private func stopEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
    }
}

// MARK: - NSPopoverDelegate

extension AppDelegate: NSPopoverDelegate {
    /// Called when the popover closes for any reason (click outside, programmatic, etc.).
    /// Unhighlights the status bar button and cleans up the event monitor.
    nonisolated func popoverDidClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            statusItem?.button?.highlight(false)
            stopEventMonitor()
        }
    }
}
