import AppKit
import SwiftUI

@MainActor
final class MenuBarPanelController {
    private weak var statusItem: NSStatusItem?
    private let shouldIgnoreAutoDismiss: @MainActor () -> Bool
    private let hostingController: NSHostingController<AnyView>
    private let panelWindow: MenuBarPanelWindow
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var appResignObserver: NSObjectProtocol?

    init<Content: View>(
        statusItem: NSStatusItem,
        contentSize: CGSize,
        shouldIgnoreAutoDismiss: @escaping @MainActor () -> Bool,
        onMoveUp: @escaping @MainActor () -> Void,
        onMoveDown: @escaping @MainActor () -> Void,
        onDelete: @escaping @MainActor () -> Void,
        onPaste: @escaping @MainActor () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.statusItem = statusItem
        self.shouldIgnoreAutoDismiss = shouldIgnoreAutoDismiss
        self.hostingController = NSHostingController(rootView: AnyView(content()))
        self.panelWindow = MenuBarPanelWindow(contentSize: contentSize)
        self.panelWindow.onEscape = { [weak self] in
            self?.close()
        }
        self.panelWindow.onMoveUp = onMoveUp
        self.panelWindow.onMoveDown = onMoveDown
        self.panelWindow.onDelete = onDelete
        self.panelWindow.onPaste = onPaste
        self.panelWindow.onCloseCommand = { [weak self] in
            self?.close()
        }
        self.panelWindow.installContentView(hostingController.view)
    }

    var isShown: Bool {
        panelWindow.isVisible
    }

    func toggle() {
        if isShown {
            close()
        } else {
            show()
        }
    }

    func show() {
        guard let frame = currentPanelFrame() else { return }

        panelWindow.setFrame(frame, display: panelWindow.isVisible)
        startDismissalMonitoring()

        guard !panelWindow.isVisible else {
            NSApp.activate(ignoringOtherApps: true)
            panelWindow.makeKey()
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        panelWindow.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard panelWindow.isVisible else { return }
        stopDismissalMonitoring()
        panelWindow.orderOut(nil)
    }

    private func startDismissalMonitoring() {
        guard localMouseMonitor == nil, globalMouseMonitor == nil, appResignObserver == nil else {
            return
        }

        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseUp, .rightMouseUp, .otherMouseUp]
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self] event in
            self?.dismissIfNeeded(for: event)
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self] event in
            self?.dismissIfNeeded(for: event)
        }
        appResignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleApplicationDidResignActive()
            }
        }
    }

    private func stopDismissalMonitoring() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let appResignObserver {
            NotificationCenter.default.removeObserver(appResignObserver)
            self.appResignObserver = nil
        }
    }

    private func handleApplicationDidResignActive() {
        guard panelWindow.isVisible else { return }
        guard !shouldIgnoreAutoDismiss() else { return }
        guard NSEvent.pressedMouseButtons == 0 else { return }
        close()
    }

    private func dismissIfNeeded(for event: NSEvent) {
        guard panelWindow.isVisible else { return }
        guard !shouldIgnoreAutoDismiss() else { return }

        let point: CGPoint = screenLocation(for: event)
        if panelWindow.frame.contains(point) {
            return
        }
        if let statusItemFrame = currentStatusItemFrame(), statusItemFrame.contains(point) {
            return
        }

        close()
    }

    private func currentPanelFrame() -> CGRect? {
        guard let statusItemFrame = currentStatusItemFrame(),
              let screenVisibleFrame = currentScreenVisibleFrame() else {
            return nil
        }

        return MenuBarPanelLayout.frame(
            panelSize: panelWindow.frame.size,
            statusItemFrame: statusItemFrame,
            screenVisibleFrame: screenVisibleFrame
        )
    }

    private func currentStatusItemFrame() -> CGRect? {
        guard let button = statusItem?.button,
              let buttonWindow = button.window else {
            return nil
        }

        let frameInWindow: NSRect = button.convert(button.bounds, to: nil)
        return buttonWindow.convertToScreen(frameInWindow)
    }

    private func currentScreenVisibleFrame() -> CGRect? {
        if let buttonScreen = statusItem?.button?.window?.screen {
            return buttonScreen.visibleFrame
        }
        return NSScreen.main?.visibleFrame
    }

    private func screenLocation(for event: NSEvent) -> CGPoint {
        if let window = event.window {
            let rectInWindow: NSRect = NSRect(origin: event.locationInWindow, size: .zero)
            return window.convertToScreen(rectInWindow).origin
        }
        return NSEvent.mouseLocation
    }
}
