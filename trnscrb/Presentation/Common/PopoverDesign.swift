import AppKit
import SwiftUI

enum PopoverDesign {
    static let popoverSize: CGSize = CGSize(width: 360, height: 560)

    static let contentPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 16
    static let cardPadding: CGFloat = 16
    static let cardCornerRadius: CGFloat = 14
    static let rowVerticalPadding: CGFloat = 10
    static let rowHorizontalPadding: CGFloat = 12
    static let rowCornerRadius: CGFloat = 12
    static let rowMinHeight: CGFloat = 64
    static let rowSpacing: CGFloat = 8
    static let fieldGroupSpacing: CGFloat = 14
    static let chromeBarHeight: CGFloat = 48
    static let chromeHorizontalPadding: CGFloat = 16
    static let dropZoneCornerRadius: CGFloat = 14
    static let dropZoneFullHeight: CGFloat = 208
    static let rowBadgeSize: CGFloat = 36
    static let rowBadgeSymbolSize: CGFloat = 16
    static let largeIconBadgeSize: CGFloat = 56
    static let largeIconSymbolSize: CGFloat = 24
    static let compactIconBadgeSize: CGFloat = 36
    static let compactIconSymbolSize: CGFloat = 16
    static let actionButtonSize: CGFloat = 22
    static let actionButtonSymbolSize: CGFloat = 11
    static let actionButtonSpacing: CGFloat = 4
    static let completionActionsWidth: CGFloat = 48

    static let primaryRowFont: Font = .system(size: 14, weight: .medium)
    static let sectionLabelFont: Font = .system(size: 13, weight: .semibold)
    static let settingsLabelFont: Font = .system(size: 13, weight: .semibold)
    static let secondaryTextFont: Font = .system(size: 12, weight: .regular)
    static let dropZoneTitleFont: Font = .system(size: 15, weight: .semibold)

    static var surfaceBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    static var cardBackground: Color {
        Color(nsColor: .controlBackgroundColor).opacity(0.85)
    }

    static var cardBorder: Color {
        Color.primary.opacity(0.08)
    }

    static var rowHoverBackground: Color {
        Color.primary.opacity(0.05)
    }

    static var rowSelectedBackground: Color {
        Color.accentColor.opacity(0.14)
    }

    static var previewBackground: Color {
        Color.primary.opacity(0.05)
    }

    static var dropZoneIdleFill: Color {
        Color.primary.opacity(0.04)
    }

    static var dropZoneHoverFill: Color {
        Color.primary.opacity(0.06)
    }

    static var dropZoneTargetedFill: Color {
        Color.accentColor.opacity(0.12)
    }
}
