import SwiftUI

/// Section header: "SESSION" / "THIS WEEK" style
struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var subtitleColor: Color = CBColor.textMuted

    var body: some View {
        HStack {
            Text(title)
                .font(CBFont.sectionHeader)
                .foregroundStyle(CBColor.textSecondary)
                .tracking(0.6)
                .textCase(.uppercase)

            Spacer()

            if let subtitle {
                Text(subtitle)
                    .font(CBFont.smallLabel)
                    .foregroundStyle(subtitleColor)
            }
        }
    }
}
