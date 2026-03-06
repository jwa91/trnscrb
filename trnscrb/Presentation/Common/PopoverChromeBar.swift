import SwiftUI

struct PopoverChromeBar<Leading: View, Center: View, Trailing: View>: View {
    let showsDivider: Bool
    @ViewBuilder let leading: Leading
    @ViewBuilder let center: Center
    @ViewBuilder let trailing: Trailing

    init(
        showsDivider: Bool = true,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder center: () -> Center = { EmptyView() },
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.showsDivider = showsDivider
        self.leading = leading()
        self.center = center()
        self.trailing = trailing()
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 12) {
                    leading
                    Spacer(minLength: 12)
                    trailing
                }
                .padding(.horizontal, PopoverDesign.chromeHorizontalPadding)
                .frame(height: PopoverDesign.chromeBarHeight)

                center
                    .padding(.horizontal, 72)
            }
            .frame(maxWidth: .infinity)
            .background(PopoverDesign.chromeSurface)

            if showsDivider {
                Divider()
            }
        }
    }
}
