import SwiftUI

struct ChromeIconButton: View {
    let systemName: String
    let title: String
    let action: () -> Void
    var keyboardShortcut: KeyboardShortcut? = nil

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(
                    width: PopoverDesign.chromeButtonVisualSize,
                    height: PopoverDesign.chromeButtonVisualSize
                )
                .foregroundStyle(
                    isHovered
                        ? PopoverDesign.chromeButtonHoverForeground
                        : PopoverDesign.chromeButtonForeground
                )
                .contentShape(Circle())
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .frame(
            width: PopoverDesign.chromeButtonHitSize,
            height: PopoverDesign.chromeButtonHitSize
        )
        .contentShape(Circle())
        .keyboardShortcut(keyboardShortcut)
        .pointingHandCursor()
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.16), value: isHovered)
        .help(title)
        .accessibilityLabel(title)
    }
}
