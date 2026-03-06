import AppKit
import SwiftUI

enum PopoverDesign {
    static let panelSize: CGSize = CGSize(width: 360, height: 548)

    static let panelCornerRadius: CGFloat = 20
    static let contentPadding: CGFloat = 12
    static let sectionSpacing: CGFloat = 12
    static let cardCornerRadius: CGFloat = 14
    static let rowVerticalPadding: CGFloat = 8
    static let rowHorizontalPadding: CGFloat = 12
    static let rowCornerRadius: CGFloat = 12
    static let rowMinHeight: CGFloat = 56
    static let rowSpacing: CGFloat = 8
    static let fieldGroupSpacing: CGFloat = 14
    static let chromeBarHeight: CGFloat = 48
    static let chromeHorizontalPadding: CGFloat = 14
    static let chromeButtonHitSize: CGFloat = 44
    static let chromeButtonVisualSize: CGFloat = 28
    static let dropZoneCornerRadius: CGFloat = 14
    static let dropZoneFullHeight: CGFloat = 184
    static let rowBadgeSize: CGFloat = 36
    static let rowBadgeSymbolSize: CGFloat = 16
    static let largeIconBadgeSize: CGFloat = 52
    static let largeIconSymbolSize: CGFloat = 24
    static let compactIconBadgeSize: CGFloat = 34
    static let compactIconSymbolSize: CGFloat = 16
    static let actionButtonSize: CGFloat = 22
    static let actionButtonSymbolSize: CGFloat = 11
    static let actionButtonSpacing: CGFloat = 4
    static let completionActionsWidth: CGFloat = 74

    static let primaryRowFont: Font = .system(size: 14, weight: .medium)
    static let sectionLabelFont: Font = .system(size: 13, weight: .semibold)
    static let settingsLabelFont: Font = .system(size: 13, weight: .semibold)
    static let secondaryTextFont: Font = .system(size: 12, weight: .regular)
    static let dropZoneTitleFont: Font = .system(size: 15, weight: .semibold)

    static var surfaceBackground: Color {
        .clear
    }

    static var chromeSurface: Color {
        .clear
    }

    static var contentSurface: Color {
        Color.white.opacity(0.05)
    }

    static var chromeButtonForeground: Color {
        .secondary
    }

    static var chromeButtonHoverForeground: Color {
        .primary
    }

    static var rowHoverBackground: Color {
        Color.white.opacity(0.045)
    }

    static var rowSelectedBackground: Color {
        Color.accentColor.opacity(0.06)
    }

    static var dropZoneIdleFill: Color {
        contentSurface
    }

    static var dropZoneHoverFill: Color {
        Color.white.opacity(0.055)
    }

    static var dropZoneTargetedFill: Color {
        Color.accentColor.opacity(0.08)
    }

    static var dropZoneIdleStroke: Color {
        Color.secondary.opacity(0.3)
    }

    static var dropZoneHoverStroke: Color {
        Color.secondary.opacity(0.46)
    }

    static var dropZoneActiveStroke: Color {
        Color.accentColor.opacity(0.92)
    }

    static var dropZoneIdleBadgeFill: Color {
        Color.primary.opacity(0.06)
    }

    static var dropZoneHoverBadgeFill: Color {
        Color.primary.opacity(0.09)
    }

    static var dropZoneActiveBadgeFill: Color {
        Color.accentColor.opacity(0.18)
    }
}
