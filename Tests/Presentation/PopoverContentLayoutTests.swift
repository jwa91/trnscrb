import Testing

@testable import trnscrb

struct PopoverContentLayoutTests {
    @Test func usesFullDropZoneWhenNoJobsExist() {
        let layout: PopoverContentLayout = PopoverContentLayout(
            activeJobCount: 0,
            completedJobCount: 0
        )

        #expect(layout.dropZoneMode == .full)
    }

    @Test func keepsCompactDropZoneVisibleWhileJobsAreActive() {
        let layout: PopoverContentLayout = PopoverContentLayout(
            activeJobCount: 2,
            completedJobCount: 0
        )

        #expect(layout.dropZoneMode == .compact)
    }

    @Test func usesCompactDropZoneWhenOnlyCompletedJobsExist() {
        let layout: PopoverContentLayout = PopoverContentLayout(
            activeJobCount: 0,
            completedJobCount: 4
        )

        #expect(layout.dropZoneMode == .compact)
    }
}
