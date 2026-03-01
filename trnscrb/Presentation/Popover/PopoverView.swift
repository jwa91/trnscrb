import SwiftUI

/// Root view displayed inside the menu bar popover.
///
/// Shows the main content area (drop zone placeholder) with a footer
/// containing a gear icon to navigate to settings.
struct PopoverView: View {
    /// Controls whether the settings panel is visible.
    @State private var showSettings: Bool = false
    /// View model for the settings panel.
    @ObservedObject var settingsViewModel: SettingsViewModel

    var body: some View {
        if showSettings {
            SettingsPanel(
                viewModel: settingsViewModel,
                onBack: { showSettings = false }
            )
        } else {
            mainContent
        }
    }

    /// Main content shown when settings is not active.
    private var mainContent: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Drop files here")
                .font(.headline)
                .padding(.top, 8)
            Text("or drag onto the menu bar icon")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Divider()
            HStack {
                Spacer()
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gear")
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
        }
        .frame(width: 320, height: 360)
    }
}

/// Temporary stub — replaced in Task 5 with the real settings view.
private struct SettingsPanel: View {
    @ObservedObject var viewModel: SettingsViewModel
    var onBack: () -> Void

    var body: some View {
        VStack {
            Button("Back", action: onBack)
            Text("Settings (coming in Task 5)")
        }
        .frame(width: 320, height: 360)
    }
}
