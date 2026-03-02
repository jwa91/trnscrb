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
    /// Job list view model — retained for status bar drop forwarding.
    private var jobListViewModel: JobListViewModel?
    /// Monitors clicks outside the popover to dismiss it.
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Build infrastructure
        let keychainStore: KeychainStore = KeychainStore()
        let gateway: TOMLConfigManager = TOMLConfigManager(keychainStore: keychainStore)
        settingsGateway = gateway

        let s3Client: S3Client = S3Client(settingsGateway: gateway)
        let audioProvider: MistralAudioProvider = MistralAudioProvider(settingsGateway: gateway)
        let ocrProvider: MistralOCRProvider = MistralOCRProvider(settingsGateway: gateway)
        let clipboardDelivery: ClipboardDelivery = ClipboardDelivery()
        let fileDelivery: FileDelivery = FileDelivery(settingsGateway: gateway)
        let compositeDelivery: CompositeDelivery = CompositeDelivery(
            clipboard: clipboardDelivery,
            file: fileDelivery,
            settingsGateway: gateway
        )

        // Build use case
        let useCase: ProcessFileUseCase = ProcessFileUseCase(
            storage: s3Client,
            transcribers: [audioProvider, ocrProvider],
            delivery: compositeDelivery,
            settings: gateway
        )

        // Build presentation
        let settingsVM: SettingsViewModel = SettingsViewModel(gateway: gateway)
        let jobListVM: JobListViewModel = JobListViewModel(
            useCase: useCase,
            settingsGateway: gateway
        )
        self.jobListViewModel = jobListVM

        // Setup popover — use .applicationDefined so it doesn't dismiss
        // when the user clicks Finder to start a drag operation.
        let popover: NSPopover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 360)
        popover.behavior = .applicationDefined
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(
                settingsViewModel: settingsVM,
                jobListViewModel: jobListVM
            )
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
            // Avoid known right-click highlight sticking bug (Jesse Squires).
            button.sendAction(on: [.leftMouseDown, .rightMouseUp])

            // Add drop target overlay
            let dropView: StatusBarDropView = StatusBarDropView(frame: button.bounds)
            dropView.autoresizingMask = [.width, .height]
            dropView.onDrop = { [weak self, weak jobListVM] urls in
                jobListVM?.processFiles(urls)
                self?.showPopover()
            }
            dropView.onDragEntered = { [weak self] in
                self?.statusItem?.button?.image = NSImage(
                    systemSymbolName: "arrow.down.doc.fill",
                    accessibilityDescription: "trnscrb drop"
                )
            }
            dropView.onDragExited = { [weak self] in
                self?.statusItem?.button?.image = NSImage(
                    systemSymbolName: "doc.text",
                    accessibilityDescription: "trnscrb"
                )
            }
            button.addSubview(dropView)
        }
        self.statusItem = statusItem
    }

    /// Toggles the popover visibility when the menu bar icon is clicked.
    @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    /// Shows the popover and starts the event monitor.
    private func showPopover() {
        guard let popover, let button = statusItem?.button else { return }
        guard !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Must be async — NSStatusBarButton resets highlight on mouse-up.
        // Dispatching to the next run loop iteration runs after that reset.
        DispatchQueue.main.async {
            button.isHighlighted = true
        }
        startEventMonitor()
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
        DispatchQueue.main.async { @MainActor in
            self.statusItem?.button?.isHighlighted = false
            self.stopEventMonitor()
        }
    }
}
