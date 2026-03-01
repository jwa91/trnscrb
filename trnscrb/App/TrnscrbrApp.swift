import SwiftUI

/// Main entry point for the trnscrb menu bar app.
@main
struct TrnscrbrApp: App {
    var body: some Scene {
        MenuBarExtra("trnscrb", systemImage: "doc.text") {
            Text("trnscrb")
        }
    }
}
