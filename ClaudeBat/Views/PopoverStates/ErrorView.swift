import SwiftUI

struct ErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Dead bat
            PixelBatView(expression: .dead, pixelSize: 4, color: CBColor.batteryCritical)

            Spacer().frame(height: 16)

            Text("Connection Failed")
                .font(CBFont.pixelFont(size: 11))
                .foregroundStyle(CBColor.textPrimary)

            Spacer().frame(height: 8)

            Text("Retrying automatically")
                .font(CBFont.modelLabel)
                .foregroundStyle(CBColor.textMuted)

            Spacer()
        }
        .padding(.horizontal, CBSpacing.popupPadding)
    }
}
