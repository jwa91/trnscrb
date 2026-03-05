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
    /// Shared route state for the popover's main and settings screens.
    private let popoverNavigationModel: PopoverNavigationModel = PopoverNavigationModel()
    /// Tracks when the file picker panel is open so drag targets can disable safely.
    private let filePickerPresentationModel: FilePickerPresentationModel = FilePickerPresentationModel()
    /// Settings gateway for the lifetime of the app.
    private var settingsGateway: (any SettingsGateway)?
    /// Job list view model — retained for status bar drop forwarding.
    private var jobListViewModel: JobListViewModel?
    /// Background retention cleanup use case.
    private var cleanupUseCase: CleanupRetentionUseCase?
    /// Applies launch-at-login settings at startup and from the settings screen.
    private var launchAtLoginUseCase: ApplyLaunchAtLoginUseCase?
    /// Timer driving periodic retention cleanup.
    private var retentionTimer: Timer?
    /// Prevents retention cleanup from overlapping across timer ticks.
    private let retentionCleanupCoordinator: RetentionCleanupCoordinator = RetentionCleanupCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Build infrastructure
        let keychainStore: KeychainStore = KeychainStore()
        let gateway: TOMLConfigManager = TOMLConfigManager(keychainStore: keychainStore)
        settingsGateway = gateway
        let outputFolderClient: OutputFolderClient = OutputFolderClient()

        let s3Client: S3Client = S3Client(settingsGateway: gateway)
        let audioProvider: MistralAudioProvider = MistralAudioProvider(settingsGateway: gateway)
        let ocrProvider: MistralOCRProvider = MistralOCRProvider(settingsGateway: gateway)
        let localAudioProvider: AppleSpeechAnalyzerProvider = AppleSpeechAnalyzerProvider()
        let localDocumentProvider: AppleDocumentOCRProvider = AppleDocumentOCRProvider()
        let clipboardDelivery: ClipboardDelivery = ClipboardDelivery()
        let fileDelivery: FileDelivery = FileDelivery(
            settingsGateway: gateway,
            outputFolderGateway: outputFolderClient
        )
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
            outputFolderGateway: outputFolderClient,
            launchAtLoginUseCase: launchAtLoginUseCase
        )
        if NotificationRuntimeSupport.areUserNotificationsSupported() {
            UNUserNotificationCenter.current().delegate = self
        }

        // Build use case
        let isLocalModeAvailable: @Sendable () -> Bool = {
            if #available(macOS 26, *) {
                return true
            }
            return false
        }
        let useCase: ProcessFileUseCase = ProcessFileUseCase(
            storage: s3Client,
            transcribers: [audioProvider, ocrProvider, localAudioProvider, localDocumentProvider],
            delivery: compositeDelivery,
            settings: gateway,
            isLocalModeAvailable: isLocalModeAvailable
        )
        cleanupUseCase = CleanupRetentionUseCase(storage: s3Client, settings: gateway)

        // Build presentation
        let settingsVM: SettingsViewModel = SettingsViewModel(
            gateway: gateway,
            connectivityUseCase: connectivityUseCase,
            outputFolderGateway: outputFolderClient,
            saveSettingsUseCase: saveSettingsUseCase
        )
        let jobListVM: JobListViewModel = JobListViewModel(
            useCase: useCase,
            settingsGateway: gateway,
            outputFolderGateway: outputFolderClient,
            notificationUseCase: notificationUseCase,
            isLocalModeAvailable: isLocalModeAvailable
        )
        self.jobListViewModel = jobListVM

        // Setup popover with macOS-managed semitransient behavior:
        // it stays open for cross-app interactions like Finder drags,
        // but dismisses on appropriate local interactions.
        let popover: NSPopover = NSPopover()
        popover.contentSize = NSSize(
            width: PopoverDesign.popoverSize.width,
            height: PopoverDesign.popoverSize.height
        )
        popover.behavior = .semitransient
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(
                navigationModel: popoverNavigationModel,
                filePickerPresentationModel: filePickerPresentationModel,
                settingsViewModel: settingsVM,
                jobListViewModel: jobListVM,
                onClose: { [weak self] in
                    self?.closePopover()
                }
            )
        )
        self.popover = popover

        // Setup status item
        let statusItem: NSStatusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        if let button: NSStatusBarButton = statusItem.button {
            button.image = makeStatusItemImage()
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
                self?.showPopover(route: .main)
            }
            dropView.onDragEntered = { [weak self] in
                self?.statusItem?.button?.image = NSImage(
                    systemSymbolName: "arrow.down.doc.fill",
                    accessibilityDescription: "Drop files to transcribe"
                )
                self?.statusItem?.button?.image?.isTemplate = true
                self?.statusItem?.button?.setAccessibilityLabel("Drop files to transcribe")
            }
            dropView.onDragExited = { [weak self] in
                self?.statusItem?.button?.image = self?.makeStatusItemImage()
                self?.statusItem?.button?.setAccessibilityLabel("trnscrb menu bar item")
            }
            button.addSubview(dropView)
        }
        self.statusItem = statusItem

        Task { @MainActor [weak self] in
            await self?.applyLaunchAtLoginSetting()
        }
        scheduleRetentionCleanup()
        triggerRetentionCleanup()
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

    func showSettingsFromCommand() {
        showPopover(route: .settings)
    }

    func addFilesFromCommand() {
        showPopover(route: .main)
        let urls: [URL] = filePickerPresentationModel.pickFiles()
        guard !urls.isEmpty else { return }
        jobListViewModel?.processFiles(urls)
    }

    private func showPopover(route: PopoverRoute) {
        switch route {
        case .main:
            popoverNavigationModel.showMain()
        case .settings:
            popoverNavigationModel.showSettings()
        }
        showPopover()
    }

    /// Shows the popover and starts the event monitor.
    private func showPopover() {
        guard let popover, let button = statusItem?.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        guard !popover.isShown else {
            popover.contentViewController?.view.window?.makeKey()
            return
        }
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

    private func makeStatusItemImage() -> NSImage? {
        if let image = AppLogoAsset.templateImage() {
            return image
        }
        let fallback: NSImage? = NSImage(
            systemSymbolName: "doc.text",
            accessibilityDescription: "trnscrb menu bar item"
        )
        fallback?.isTemplate = true
        return fallback
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
            Task { @MainActor [weak self] in
                self?.triggerRetentionCleanup()
            }
        }
    }

    private func triggerRetentionCleanup() {
        retentionCleanupCoordinator.trigger { [weak self] in
            await self?.runRetentionCleanup()
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
            self.showPopover(route: .main)
            if let jobID: UUID = UUID(uuidString: identifier) {
                self.jobListViewModel?.selectJob(id: jobID)
            }
        }
    }
}
