import SwiftUI

/// Shared header for popup: bat icon + "ClaudeBat" + close button
/// Bat cycles through expressions: default → winking → cheeky → sleeping → loop
struct PopoverHeader: View {
    var onClose: (() -> Void)? = nil

    @State private var expression: BatExpression = .default
    @State private var expressionIndex = 0

    private let expressions: [BatExpression] = [.default, .winking, .cheeky, .sleeping]

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                PixelBatView(expression: expression, pixelSize: 1.5, color: CBColor.accent)
                Text("ClaudeBat")
                    .font(CBFont.pixelFont(size: 14))
                    .foregroundStyle(CBColor.accent)
            }

            Spacer()

            if let onClose {
                PixelCloseButton(action: onClose)
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                expressionIndex = (expressionIndex + 1) % expressions.count
                expression = expressions[expressionIndex]
            }
        }
    }
}
