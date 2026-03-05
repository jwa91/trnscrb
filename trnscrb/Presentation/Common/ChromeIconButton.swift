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
                .frame(width: 32, height: 32)
                .foregroundStyle(isHovered ? Color.primary : Color.secondary)
                .background(
                    Circle()
                        .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(keyboardShortcut)
        .pointingHandCursor()
        .onHover { isHovered = $0 }
        .help(title)
        .accessibilityLabel(title)
    }
}
