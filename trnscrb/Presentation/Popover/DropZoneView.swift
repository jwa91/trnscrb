import SwiftUI
import UniformTypeIdentifiers

/// A drop zone that accepts files via drag-and-drop or a file picker fallback.
///
/// Shows a visual target area with hover feedback. Validates file types
/// using `FileType.allSupported` and calls `onDrop` with valid URLs.
struct DropZoneView: View {
    enum Mode {
        case full
        case compact
    }

    /// Called with the URLs of dropped/selected files.
    var onDrop: ([URL]) -> Void
    /// Layout variant for the idle or inline uploader state.
    var mode: Mode = .full
    /// Tracks whether a drag is hovering over the zone.
    @State private var isTargeted: Bool = false
    /// Tracks whether the pointer is hovering over the zone.
    @State private var isHovered: Bool = false

    var body: some View {
        content
            .frame(
                maxWidth: .infinity,
                minHeight: mode == .full ? PopoverDesign.dropZoneFullHeight : nil,
                alignment: mode == .full ? .center : .leading
            )
            .padding(mode == .full ? 24 : 16)
            .background(
                RoundedRectangle(
                    cornerRadius: PopoverDesign.dropZoneCornerRadius,
                    style: .continuous
                )
                .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: PopoverDesign.dropZoneCornerRadius,
                    style: .continuous
                )
                .strokeBorder(
                    borderColor,
                    style: StrokeStyle(lineWidth: borderLineWidth, dash: [8, 6])
                )
            )
            .contentShape(
                RoundedRectangle(
                    cornerRadius: PopoverDesign.dropZoneCornerRadius,
                    style: .continuous
                )
            )
            .pointingHandCursor()
            .onTapGesture {
                openFilePicker()
            }
            .onHover { isHovered = $0 }
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers)
            }
            .animation(.easeOut(duration: 0.16), value: isHovered)
            .animation(.easeOut(duration: 0.16), value: isTargeted)
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .full:
            VStack(spacing: 12) {
                iconBadge(
                    size: PopoverDesign.largeIconBadgeSize,
                    symbolSize: PopoverDesign.largeIconSymbolSize
                )

                Text("Drop audio, PDFs, and images here")
                    .font(PopoverDesign.dropZoneTitleFont)
                    .multilineTextAlignment(.center)

                Text("or click to browse")
                    .font(PopoverDesign.secondaryTextFont)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        case .compact:
            HStack(spacing: 12) {
                iconBadge(
                    size: PopoverDesign.compactIconBadgeSize,
                    symbolSize: PopoverDesign.compactIconSymbolSize
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Add files")
                        .font(PopoverDesign.sectionLabelFont)
                    Text("Audio, PDFs, and images")
                        .font(PopoverDesign.secondaryTextFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
            }
        }
    }

    private func iconBadge(size: CGFloat, symbolSize: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Color.accentColor.opacity(isTargeted ? 0.24 : 0.16))

            Image(systemName: "square.and.arrow.down.fill")
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(isHovered || isTargeted ? Color.accentColor : Color.primary)
        }
        .frame(width: size, height: size)
    }

    private var backgroundColor: Color {
        if isTargeted {
            return PopoverDesign.dropZoneTargetedFill
        }
        if isHovered {
            return PopoverDesign.dropZoneHoverFill
        }
        return PopoverDesign.dropZoneIdleFill
    }

    private var borderColor: Color {
        if isTargeted {
            return Color.accentColor
        }
        if isHovered {
            return Color.secondary.opacity(0.55)
        }
        return Color.secondary.opacity(0.35)
    }

    private var borderLineWidth: CGFloat {
        isTargeted ? 2 : 1.2
    }

    /// Extracts file URLs from drop providers and calls onDrop.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        SupportedFileImport.loadFileURLs(from: providers) { urls in
            if !urls.isEmpty {
                onDrop(urls)
            }
        }
        return true
    }

    /// Opens a macOS file picker dialog for selecting files.
    private func openFilePicker() {
        let urls: [URL] = SupportedFilePicker.pickFiles()
        guard !urls.isEmpty else { return }
        onDrop(urls)
    }
}
