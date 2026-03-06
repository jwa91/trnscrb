import AppKit

@MainActor
final class MenuBarPanelWindow: NSPanel {
    private let backgroundView: NSVisualEffectView = NSVisualEffectView()
    private let tintView: NSView = NSView()
    private let contentContainerView: NSView = NSView()

    var onEscape: (() -> Void)?
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onDelete: (() -> Void)?
    var onPaste: (() -> Void)?
    var onCloseCommand: (() -> Void)?

    init(contentSize: CGSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        animationBehavior = .utilityWindow
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        worksWhenModal = true

        configureBackgroundView()
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, handleKeyEvent(event) {
            return
        }
        super.sendEvent(event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }

    func installContentView(_ view: NSView) {
        contentContainerView.subviews.forEach { $0.removeFromSuperview() }

        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.focusRingType = .none
        contentContainerView.focusRingType = .none
        backgroundView.focusRingType = .none
        contentContainerView.addSubview(view)

        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
            view.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
            view.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor),
        ])
    }

    private func configureBackgroundView() {
        backgroundView.blendingMode = .behindWindow
        backgroundView.material = .menu
        backgroundView.state = .active
        backgroundView.isEmphasized = false
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = PopoverDesign.panelCornerRadius
        backgroundView.layer?.cornerCurve = .continuous
        backgroundView.layer?.borderWidth = 1
        backgroundView.layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
        backgroundView.layer?.masksToBounds = true

        tintView.translatesAutoresizingMaskIntoConstraints = false
        tintView.wantsLayer = true
        tintView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.14).cgColor

        contentContainerView.translatesAutoresizingMaskIntoConstraints = false
        contentContainerView.wantsLayer = true
        contentContainerView.layer?.backgroundColor = NSColor.clear.cgColor

        backgroundView.addSubview(tintView)
        backgroundView.addSubview(contentContainerView)
        contentView = backgroundView

        NSLayoutConstraint.activate([
            tintView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            tintView.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            tintView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),
            contentContainerView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            contentContainerView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            contentContainerView.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            contentContainerView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),
        ])
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let modifierFlags: NSEvent.ModifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifierFlags == [.command], let characters = event.charactersIgnoringModifiers?.lowercased() {
            switch characters {
            case "v":
                onPaste?()
                return true
            case "w":
                onCloseCommand?()
                return true
            default:
                break
            }
        }

        switch event.keyCode {
        case 53:
            onEscape?()
            return true
        case 51, 117:
            onDelete?()
            return true
        case 126:
            onMoveUp?()
            return true
        case 125:
            onMoveDown?()
            return true
        default:
            return false
        }
    }
}
