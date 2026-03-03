import AppKit
import SwiftUI

private struct PointingHandOnHoverModifier: ViewModifier {
    @State private var isCursorPushed: Bool = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovered in
                if isHovered {
                    guard !isCursorPushed else { return }
                    NSCursor.pointingHand.push()
                    isCursorPushed = true
                    return
                }

                guard isCursorPushed else { return }
                NSCursor.pop()
                isCursorPushed = false
            }
            .onDisappear {
                guard isCursorPushed else { return }
                NSCursor.pop()
                isCursorPushed = false
            }
    }
}

extension View {
    func pointingHandCursor() -> some View {
        modifier(PointingHandOnHoverModifier())
    }
}
