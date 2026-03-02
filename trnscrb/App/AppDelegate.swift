import AppKit
import SwiftUI
import UserNotifications

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
    /// Background retention cleanup use case.
    private var cleanupUseCase: CleanupRetentionUseCase?
    /// Applies launch-at-login settings at startup and from the settings screen.
    private var launchAtLoginUseCase: ApplyLaunchAtLoginUseCase?
    /// Persists settings and secrets as a single use case for the settings screen.
    private var saveSettingsUseCase: SaveSettingsUseCase?
    /// Timer driving periodic retention cleanup.
    private var retentionTimer: Timer?

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
        let notificationUseCase: NotifyUserUseCase = NotifyUserUseCase(
            gateway: UserNotificationClient()
        )
        let connectivityClient: ConnectivityClient = ConnectivityClient()
        let connectivityUseCase: TestConnectivityUseCase = TestConnectivityUseCase(
            gateway: connectivityClient
        )
        let launchAtLoginUseCase: ApplyLaunchAtLoginUseCase = ApplyLaunchAtLoginUseCase(
            gateway: LaunchAtLoginManager()
        )
        self.launchAtLoginUseCase = launchAtLoginUseCase
        let saveSettingsUseCase: SaveSettingsUseCase = SaveSettingsUseCase(
            gateway: gateway,
            launchAtLoginUseCase: launchAtLoginUseCase
        )
        self.saveSettingsUseCase = saveSettingsUseCase
        UNUserNotificationCenter.current().delegate = self

        // Build use case
        let useCase: ProcessFileUseCase = ProcessFileUseCase(
            storage: s3Client,
            transcribers: [audioProvider, ocrProvider],
            delivery: compositeDelivery,
            settings: gateway
        )
        cleanupUseCase = CleanupRetentionUseCase(storage: s3Client, settings: gateway)

        // Build presentation
        let settingsVM: SettingsViewModel = SettingsViewModel(
            gateway: gateway,
            connectivityUseCase: connectivityUseCase,
            saveSettingsUseCase: saveSettingsUseCase
        )
        let jobListVM: JobListViewModel = JobListViewModel(
            useCase: useCase,
            settingsGateway: gateway,
            notificationUseCase: notificationUseCase
        )
        self.jobListViewModel = jobListVM

        // Setup popover with macOS-managed semitransient behavior:
        // it stays open for cross-app interactions like Finder drags,
        // but dismisses on appropriate local interactions.
        let popover: NSPopover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 480)
        popover.behavior = .semitransient
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
                accessibilityDescription: "trnscrb menu bar item"
            )
            button.setAccessibilityLabel("trnscrb menu bar item")
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
                    accessibilityDescription: "Drop files to transcribe"
                )
                self?.statusItem?.button?.setAccessibilityLabel("Drop files to transcribe")
            }
            dropView.onDragExited = { [weak self] in
                self?.statusItem?.button?.image = NSImage(
                    systemSymbolName: "doc.text",
                    accessibilityDescription: "trnscrb menu bar item"
                )
                self?.statusItem?.button?.setAccessibilityLabel("trnscrb menu bar item")
            }
            button.addSubview(dropView)
        }
        self.statusItem = statusItem

        Task { @MainActor [weak self] in
            await self?.applyLaunchAtLoginSetting()
            await self?.runRetentionCleanup()
        }
        scheduleRetentionCleanup()
    }

    /// Toggles the popover visibility when the menu bar icon is clicked.
    @objc private func togglePopover() {
        guard let popover else { return }
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
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        // Must be async — NSStatusBarButton resets highlight on mouse-up.
        // Dispatching to the next run loop iteration runs after that reset.
        DispatchQueue.main.async {
            button.isHighlighted = true
        }
    }

    /// Closes the popover and removes the event monitor.
    private func closePopover() {
        popover?.performClose(nil)
    }

    private func applyLaunchAtLoginSetting() async {
        guard let settingsGateway, let launchAtLoginUseCase else { return }
        do {
            let settings: AppSettings = try await settingsGateway.loadSettings()
            try await launchAtLoginUseCase.apply(enabled: settings.launchAtLogin)
        } catch {
            // Keep launch behavior best-effort; invalid permissions/config should not crash the app.
        }
    }

    private func scheduleRetentionCleanup() {
        retentionTimer?.invalidate()
        retentionTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.runRetentionCleanup()
            }
        }
    }

    private func runRetentionCleanup() async {
        guard let cleanupUseCase else { return }
        do {
            try await cleanupUseCase.execute()
        } catch {
            // Cleanup errors are non-fatal and retried on the next timer tick.
        }
    }
}

// MARK: - NSPopoverDelegate

extension AppDelegate: NSPopoverDelegate {
    /// Called when the popover closes for any reason (click outside, programmatic, etc.).
    /// Unhighlights the status bar button.
    nonisolated func popoverDidClose(_ notification: Notification) {
        DispatchQueue.main.async { @MainActor in
            self.statusItem?.button?.isHighlighted = false
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier: String = response.notification.request.identifier
        await MainActor.run {
            self.showPopover()
            if let jobID: UUID = UUID(uuidString: identifier) {
                self.jobListViewModel?.selectJob(id: jobID)
            }
        }
    }
}
