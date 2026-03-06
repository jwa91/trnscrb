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
    /// Opens the shared file picker flow.
    var onSelectFiles: () -> Void
    /// Layout variant for the idle or inline uploader state.
    var mode: Mode = .full
    /// True while the file picker panel is open and panel-origin drags are unsupported.
    var isFilePickerPresented: Bool = false
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
            .padding(mode == .full ? 20 : 14)
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
            .onHover { isHovered = $0 }
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                guard !isFilePickerPresented else { return false }
                return handleDrop(providers)
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

                Text(isFilePickerPresented ? "File picker is open" : "Drop audio, PDFs, and images here")
                    .font(PopoverDesign.dropZoneTitleFont)
                    .multilineTextAlignment(.center)

                if isFilePickerPresented {
                    Text("Choose files in that window, or drag from Finder after closing it.")
                        .font(PopoverDesign.secondaryTextFont)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    browseButton
                }
            }
            .frame(maxWidth: .infinity)
        case .compact:
            HStack(spacing: 12) {
                iconBadge(
                    size: PopoverDesign.compactIconBadgeSize,
                    symbolSize: PopoverDesign.compactIconSymbolSize
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(isFilePickerPresented ? "File picker open" : "Add files")
                        .font(PopoverDesign.sectionLabelFont)
                    Text(
                        isFilePickerPresented
                            ? "Choose there, or drag from Finder after closing it"
                            : "Audio, PDFs, and images"
                    )
                        .font(PopoverDesign.secondaryTextFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !isFilePickerPresented {
                    browseButton
                }
                Spacer(minLength: 8)
            }
        }
    }

    private var browseButton: some View {
        Button("Select files…") {
            onSelectFiles()
        }
        .buttonStyle(.glass)
        .controlSize(.regular)
        .font(PopoverDesign.secondaryTextFont)
        .pointingHandCursor()
    }

    private func iconBadge(size: CGFloat, symbolSize: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(iconBackgroundColor)

            Image(systemName: "square.and.arrow.down.fill")
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(iconForegroundColor)
        }
        .frame(width: size, height: size)
    }

    private var backgroundColor: Color {
        if isFilePickerPresented {
            return PopoverDesign.dropZoneIdleFill.opacity(0.75)
        }
        if isTargeted {
            return PopoverDesign.dropZoneTargetedFill
        }
        if isHovered {
            return PopoverDesign.dropZoneHoverFill
        }
        return PopoverDesign.dropZoneIdleFill
    }

    private var borderColor: Color {
        if isFilePickerPresented {
            return PopoverDesign.dropZoneIdleStroke
        }
        if isTargeted {
            return PopoverDesign.dropZoneActiveStroke
        }
        if isHovered {
            return PopoverDesign.dropZoneHoverStroke
        }
        return PopoverDesign.dropZoneIdleStroke
    }

    private var borderLineWidth: CGFloat {
        if isFilePickerPresented {
            return 1
        }
        return isTargeted ? 2 : 1.2
    }

    private var iconBackgroundColor: Color {
        if isFilePickerPresented {
            return Color.secondary.opacity(0.12)
        }
        if isTargeted {
            return PopoverDesign.dropZoneActiveBadgeFill
        }
        if isHovered {
            return PopoverDesign.dropZoneHoverBadgeFill
        }
        return PopoverDesign.dropZoneIdleBadgeFill
    }

    private var iconForegroundColor: Color {
        if isFilePickerPresented {
            return Color.secondary
        }
        if isTargeted {
            return Color.accentColor
        }
        return isHovered ? Color.primary : Color.secondary
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
}
