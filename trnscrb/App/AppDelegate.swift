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
    /// The dedicated settings window for app configuration.
    private var settingsWindowController: NSWindowController?
    /// Tracks when the file picker panel is open so drag targets can disable safely.
    private let filePickerPresentationModel: FilePickerPresentationModel = FilePickerPresentationModel()
    /// Timer driving periodic retention cleanup.
    private var retentionTimer: Timer?
    /// Prevents retention cleanup from overlapping across timer ticks.
    private let retentionCleanupCoordinator: RetentionCleanupCoordinator = RetentionCleanupCoordinator()
    /// Evaluates whether local Apple mode is available on this runtime.
    private let isLocalModeAvailable: @Sendable () -> Bool = {
        if #available(macOS 26, *) {
            return true
        }
        return false
    }

    private lazy var settingsGateway: any SettingsGateway = {
        TOMLConfigManager(keychainStore: KeychainStore())
    }()
    private lazy var outputFolderClient: OutputFolderClient = OutputFolderClient()
    private lazy var s3Client: S3Client = S3Client(settingsGateway: settingsGateway)
    private lazy var audioProvider: MistralAudioProvider = MistralAudioProvider(
        settingsGateway: settingsGateway
    )
    private lazy var ocrProvider: MistralOCRProvider = MistralOCRProvider(
        settingsGateway: settingsGateway
    )
    private lazy var localAudioProvider: AppleSpeechAnalyzerProvider = AppleSpeechAnalyzerProvider(
        settingsGateway: settingsGateway,
        isLocalModeAvailable: isLocalModeAvailable
    )
    private lazy var localDocumentProvider: AppleDocumentOCRProvider = AppleDocumentOCRProvider()
    private lazy var compositeDelivery: CompositeDelivery = CompositeDelivery(
        clipboard: ClipboardDelivery(),
        file: FileDelivery(
            settingsGateway: settingsGateway,
            outputFolderGateway: outputFolderClient
        ),
        settingsGateway: settingsGateway
    )
    private lazy var notificationUseCase: NotifyUserUseCase = NotifyUserUseCase(
        gateway: UserNotificationClient()
    )
    private lazy var connectivityUseCase: TestConnectivityUseCase = TestConnectivityUseCase(
        gateway: ConnectivityClient()
    )
    private lazy var launchAtLoginUseCase: ApplyLaunchAtLoginUseCase = ApplyLaunchAtLoginUseCase(
        gateway: LaunchAtLoginManager()
    )
    private lazy var saveSettingsUseCase: SaveSettingsUseCase = SaveSettingsUseCase(
        gateway: settingsGateway,
        outputFolderGateway: outputFolderClient,
        launchAtLoginUseCase: launchAtLoginUseCase
    )
    private lazy var processFileUseCase: ProcessFileUseCase = ProcessFileUseCase(
        storage: s3Client,
        transcribers: [audioProvider, ocrProvider, localAudioProvider, localDocumentProvider],
        delivery: compositeDelivery,
        settings: settingsGateway,
        isLocalModeAvailable: isLocalModeAvailable
    )
    private lazy var cleanupUseCase: CleanupRetentionUseCase = CleanupRetentionUseCase(
        storage: s3Client,
        settings: settingsGateway
    )
    private lazy var settingsViewModel: SettingsViewModel = SettingsViewModel(
        gateway: settingsGateway,
        connectivityUseCase: connectivityUseCase,
        outputFolderGateway: outputFolderClient,
        saveSettingsUseCase: saveSettingsUseCase,
        isLocalAppleModeAvailable: isLocalModeAvailable
    )
    private lazy var jobListViewModel: JobListViewModel = JobListViewModel(
        useCase: processFileUseCase,
        settingsGateway: settingsGateway,
        outputFolderGateway: outputFolderClient,
        notificationUseCase: notificationUseCase,
        isLocalModeAvailable: isLocalModeAvailable
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if NotificationRuntimeSupport.areUserNotificationsSupported() {
            UNUserNotificationCenter.current().delegate = self
        }

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
                filePickerPresentationModel: filePickerPresentationModel,
                jobListViewModel: jobListViewModel,
                onOpenSettings: { [weak self] in
                    self?.showSettingsFromCommand()
                },
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
            dropView.onDrop = { [weak self] urls in
                self?.jobListViewModel.processFiles(urls)
                self?.showPopover()
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
        closePopover()
        showSettingsWindow()
    }

    func addFilesFromCommand() {
        showPopover()
        let urls: [URL] = filePickerPresentationModel.pickFiles()
        guard !urls.isEmpty else { return }
        jobListViewModel.processFiles(urls)
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

    private func showSettingsWindow() {
        let controller: NSWindowController
        if let existingController = settingsWindowController {
            controller = existingController
        } else {
            controller = makeSettingsWindowController()
            settingsWindowController = controller
        }

        if controller.window?.isVisible != true {
            Task { @MainActor [weak self] in
                await self?.settingsViewModel.load()
            }
        }

        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private func closeSettingsWindow() {
        settingsWindowController?.close()
    }

    private func terminateApp() {
        NSApp.terminate(nil)
    }

    private func makeSettingsWindowController() -> NSWindowController {
        let rootView: SettingsView = SettingsView(
            viewModel: settingsViewModel,
            onClose: { [weak self] in
                self?.closeSettingsWindow()
            },
            onQuitApp: { [weak self] in
                self?.terminateApp()
            }
        )

        let window: NSWindow = NSWindow(
            contentRect: NSRect(
                origin: .zero,
                size: SettingsWindowDesign.defaultSize
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.contentViewController = NSHostingController(rootView: rootView)
        window.minSize = SettingsWindowDesign.minSize
        window.setFrameAutosaveName("trnscrb-settings")
        window.isReleasedWhenClosed = false

        return NSWindowController(window: window)
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
                self.jobListViewModel.selectJob(id: jobID)
            }
        }
    }
}
