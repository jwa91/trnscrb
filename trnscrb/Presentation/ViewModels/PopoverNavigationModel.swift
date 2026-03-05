import Foundation
import SwiftUI

@MainActor
enum PopoverRoute: Sendable, Equatable {
    case main
    case settings
}

@MainActor
final class PopoverNavigationModel: ObservableObject {
    @Published private(set) var route: PopoverRoute = .main

    func showMain() {
        route = .main
    }

    func showSettings() {
        route = .settings
    }
}
