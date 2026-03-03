import Testing

@testable import trnscrb

struct PopoverContentLayoutTests {
    @Test func idleStateUsesFullDropZone() {
        let layout: PopoverContentLayout = PopoverContentLayout(
            activeJobCount: 0,
            completedJobCount: 0
        )

        #expect(layout.dropZoneMode == .full)
    }

    @Test func recentJobsUseCompactDropZone() {
        let layout: PopoverContentLayout = PopoverContentLayout(
            activeJobCount: 0,
            completedJobCount: 2
        )

        #expect(layout.dropZoneMode == .compact)
    }

    @Test func activeJobsHideDropZone() {
        let layout: PopoverContentLayout = PopoverContentLayout(
            activeJobCount: 1,
            completedJobCount: 3
        )

        #expect(layout.dropZoneMode == .hidden)
    }
}
