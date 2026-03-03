import Foundation

enum DropZoneMode: Equatable {
    case full
    case compact
    case hidden
}

struct PopoverContentLayout: Equatable {
    let activeJobCount: Int
    let completedJobCount: Int

    var dropZoneMode: DropZoneMode {
        if activeJobCount > 0 {
            return .hidden
        }
        if completedJobCount > 0 {
            return .compact
        }
        return .full
    }
}
