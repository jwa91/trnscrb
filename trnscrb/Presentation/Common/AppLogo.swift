import AppKit
import SwiftUI

enum AppLogoAsset {
    private static func loadImage(template: Bool) -> NSImage? {
        guard let url = Bundle.module.url(forResource: "trnscrb", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = template
        return image
    }

    static func templateImage() -> NSImage? {
        loadImage(template: true)
    }
}

struct AppLogoView: View {
    var size: CGFloat = 18

    var body: some View {
        Group {
            if let image = AppLogoAsset.templateImage() {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .renderingMode(.template)
            } else {
                Image(systemName: "doc.text")
                    .resizable()
                    .renderingMode(.template)
            }
        }
        .aspectRatio(contentMode: .fit)
        .frame(width: size, height: size)
        .foregroundStyle(.primary)
        .accessibilityHidden(true)
    }
}

struct AppBrandView: View {
    var body: some View {
        HStack(spacing: 8) {
            AppLogoView(size: 18)
            Text("trnscrb")
                .font(.system(size: 14, weight: .semibold))
        }
    }
}
