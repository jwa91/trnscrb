import CoreGraphics

struct MenuBarPanelLayout {
    static let verticalGap: CGFloat = 6
    static let horizontalInset: CGFloat = 8
    static let verticalInset: CGFloat = 8

    static func frame(
        panelSize: CGSize,
        statusItemFrame: CGRect,
        screenVisibleFrame: CGRect
    ) -> CGRect {
        CGRect(
            origin: origin(
                panelSize: panelSize,
                statusItemFrame: statusItemFrame,
                screenVisibleFrame: screenVisibleFrame
            ),
            size: panelSize
        )
    }

    static func origin(
        panelSize: CGSize,
        statusItemFrame: CGRect,
        screenVisibleFrame: CGRect
    ) -> CGPoint {
        let centeredX: CGFloat = statusItemFrame.midX - (panelSize.width / 2)
        let minX: CGFloat = screenVisibleFrame.minX + horizontalInset
        let maxX: CGFloat = screenVisibleFrame.maxX - horizontalInset - panelSize.width
        let x: CGFloat
        if maxX >= minX {
            x = min(max(centeredX, minX), maxX)
        } else {
            x = screenVisibleFrame.midX - (panelSize.width / 2)
        }

        let attachmentY: CGFloat = min(statusItemFrame.minY, screenVisibleFrame.maxY)
        let proposedY: CGFloat = attachmentY - verticalGap - panelSize.height
        let minY: CGFloat = screenVisibleFrame.minY + verticalInset
        let maxY: CGFloat = screenVisibleFrame.maxY - verticalGap - panelSize.height
        let y: CGFloat
        if maxY >= minY {
            y = min(max(proposedY, minY), maxY)
        } else {
            y = screenVisibleFrame.minY
        }

        return CGPoint(
            x: x.rounded(.toNearestOrEven),
            y: y.rounded(.toNearestOrEven)
        )
    }
}
