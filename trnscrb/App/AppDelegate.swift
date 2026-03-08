import AppKit
import SwiftUI
import UserNotifications

/// Application delegate and composition root.
///
/// Creates the `NSStatusItem` (menu bar icon), manages the attached menu panel,
/// and wires all infrastructure dependencies. This is the only component
/// that knows about all layers — it creates concrete instances and injects
/// them into view models and use cases.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The menu bar status item showing the app icon.
    private var statusItem: NSStatusItem?
    /// The attached menu panel displayed when the status item is clicked.
    private var menuPanelController: MenuBarPanelController?
    /// The dedicated settings window for app configuration.
    private var settingsWindowController: NSWindowController?
    /// Tracks when the file picker panel is open so drag targets can disable safely.
    private let filePickerPresentationModel: FilePickerPresentationModel = FilePickerPresentationModel()
    /// Timer driving periodic retention cleanup.
    private var retentionTimer: Timer?
    /// Prevents retention cleanup from overlapping across timer ticks.
    private let retentionCleanupCoordinator: RetentionCleanupCoordinator = RetentionCleanupCoordinator()
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
        settingsGateway: settingsGateway
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
        settings: settingsGateway
    )
    private lazy var cleanupUseCase: CleanupRetentionUseCase = CleanupRetentionUseCase(
        storage: s3Client,
        settings: settingsGateway
    )
    private lazy var settingsViewModel: SettingsViewModel = SettingsViewModel(
        gateway: settingsGateway,
        connectivityUseCase: connectivityUseCase,
        saveSettingsUseCase: saveSettingsUseCase
    )
    private lazy var jobListViewModel: JobListViewModel = JobListViewModel(
        useCase: processFileUseCase,
        settingsGateway: settingsGateway,
        outputFolderGateway: outputFolderClient,
        notificationUseCase: notificationUseCase
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if NotificationRuntimeSupport.areUserNotificationsSupported() {
            UNUserNotificationCenter.current().delegate = self
        }

        // Setup status item
        let statusItem: NSStatusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        if let button: NSStatusBarButton = statusItem.button {
            button.image = makeStatusItemImage()
            button.setAccessibilityLabel("trnscrb menu bar item")
            button.action = #selector(toggleMenuPanel)
            button.target = self
            // Avoid known right-click highlight sticking bug (Jesse Squires).
            button.sendAction(on: [.leftMouseDown, .rightMouseUp])

            // Add drop target overlay
            let dropView: StatusBarDropView = StatusBarDropView(frame: button.bounds)
            dropView.autoresizingMask = [.width, .height]
            dropView.onDrop = { [weak self] urls in
                self?.showMenuPanel()
                self?.jobListViewModel.processFiles(urls)
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
        self.menuPanelController = MenuBarPanelController(
            statusItem: statusItem,
            contentSize: PopoverDesign.panelSize,
            shouldIgnoreAutoDismiss: { [weak self] in
                self?.filePickerPresentationModel.isPresenting ?? false
            },
            onMoveUp: { [weak self] in
                self?.jobListViewModel.selectPreviousVisibleJob()
            },
            onMoveDown: { [weak self] in
                self?.jobListViewModel.selectNextVisibleJob()
            },
            onDelete: { [weak self] in
                self?.jobListViewModel.removeSelectedOrMostRecentJob()
            },
            onPaste: { [weak self] in
                self?.processPasteboardFilesFromCommand()
            }
        ) {
            MenuPanelView(
                filePickerPresentationModel: filePickerPresentationModel,
                jobListViewModel: jobListViewModel,
                onOpenSettings: { [weak self] in
                    self?.showSettingsFromCommand()
                },
                onClose: { [weak self] in
                    self?.closeMenuPanel()
                }
            )
        }

        Task { @MainActor [weak self] in
            await self?.applyLaunchAtLoginSetting()
        }
        scheduleRetentionCleanup()
        triggerRetentionCleanup()
    }

    /// Toggles the attached menu panel visibility when the menu bar icon is clicked.
    @objc private func toggleMenuPanel() {
        guard let menuPanelController else { return }
        if menuPanelController.isShown {
            closeMenuPanel()
        } else {
            showMenuPanel()
        }
    }

    func showSettingsFromCommand() {
        closeMenuPanel()
        showSettingsWindow()
    }

    func addFilesFromCommand() {
        showMenuPanel()
        let urls: [URL] = filePickerPresentationModel.pickFiles()
        guard !urls.isEmpty else { return }
        jobListViewModel.processFiles(urls)
    }

    private func processPasteboardFilesFromCommand() {
        let pasteboard: NSPasteboard = .general
        let urls: [URL] = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []

        guard SupportedFileImport.containsSupportedFile(urls) else { return }
        jobListViewModel.processFiles(urls)
    }

    /// Shows the attached menu panel and makes it the active keyboard surface.
    private func showMenuPanel() {
        menuPanelController?.show()
    }

    /// Closes the attached menu panel and tears down dismissal monitoring.
    private func closeMenuPanel() {
        menuPanelController?.close()
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

    private func makeSettingsWindowController() -> NSWindowController {
        let rootView: SettingsView = SettingsView(
            viewModel: settingsViewModel
        )

        let window: NSWindow = NSWindow(
            contentRect: NSRect(
                origin: .zero,
                size: SettingsWindowDesign.defaultSize
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        let toolbar: NSToolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
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

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier: String = response.notification.request.identifier
        await MainActor.run {
            self.showMenuPanel()
            if let jobID: UUID = UUID(uuidString: identifier) {
                self.jobListViewModel.selectJob(id: jobID)
            }
        }
    }
}
