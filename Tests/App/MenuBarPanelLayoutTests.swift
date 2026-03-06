import CoreGraphics
import Testing

@testable import trnscrb

struct MenuBarPanelLayoutTests {
    @Test func centersPanelUnderStatusItemWhenSpaceAllows() {
        let frame: CGRect = MenuBarPanelLayout.frame(
            panelSize: CGSize(width: 360, height: 548),
            statusItemFrame: CGRect(x: 520, y: 870, width: 28, height: 22),
            screenVisibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )

        #expect(frame.origin.x == 354)
        #expect(frame.origin.y == 316)
    }

    @Test func clampsPanelNearTheLeftEdge() {
        let frame: CGRect = MenuBarPanelLayout.frame(
            panelSize: CGSize(width: 360, height: 548),
            statusItemFrame: CGRect(x: 6, y: 870, width: 28, height: 22),
            screenVisibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )

        #expect(frame.minX == MenuBarPanelLayout.horizontalInset)
    }

    @Test func clampsPanelNearTheRightEdge() {
        let frame: CGRect = MenuBarPanelLayout.frame(
            panelSize: CGSize(width: 360, height: 548),
            statusItemFrame: CGRect(x: 1406, y: 870, width: 28, height: 22),
            screenVisibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )

        #expect(frame.maxX == 1432)
    }

    @Test func remainsStableOnNarrowVisibleFrames() {
        let frame: CGRect = MenuBarPanelLayout.frame(
            panelSize: CGSize(width: 360, height: 548),
            statusItemFrame: CGRect(x: 158, y: 870, width: 28, height: 22),
            screenVisibleFrame: CGRect(x: 0, y: 0, width: 320, height: 900)
        )

        #expect(frame.origin.x == -20)
        #expect(frame.origin.y == 316)
    }
}
