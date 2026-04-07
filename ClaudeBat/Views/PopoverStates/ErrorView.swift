import SwiftUI

struct ErrorView: View {
    let titleOverride: String?
    let message: String

    init(titleOverride: String? = nil, message: String) {
        self.titleOverride = titleOverride
        self.message = message
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Dead bat
            PixelBatView(expression: .dead, pixelSize: 4, color: CBColor.batteryCritical)

            Spacer().frame(height: 16)

            Text(title)
                .font(CBFont.pixelFont(size: 11))
                .foregroundStyle(CBColor.textPrimary)

            Spacer().frame(height: 8)

            Text(message)
                .font(CBFont.modelLabel)
                .foregroundStyle(CBColor.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)

            Spacer()
        }
        .padding(.horizontal, CBSpacing.popupPadding)
    }

    private var title: String {
        if let titleOverride { return titleOverride }
        if message.localizedCaseInsensitiveContains("auth") {
            return "Auth Required"
        }
        return "Connection Failed"
    }
}
