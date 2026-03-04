import SwiftUI

struct SettingsSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PopoverDesign.sectionSpacing) {
            Text(title)
                .font(PopoverDesign.sectionLabelFont)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: PopoverDesign.fieldGroupSpacing) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(PopoverDesign.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(
                cornerRadius: PopoverDesign.cardCornerRadius,
                style: .continuous
            )
            .fill(PopoverDesign.cardBackground)
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: PopoverDesign.cardCornerRadius,
                style: .continuous
            )
            .strokeBorder(PopoverDesign.cardBorder, lineWidth: 1)
        )
    }
}
