import SwiftUI

struct LoadingRetroView: View {
    let title: String
    let message: String?

    @State private var filledSegments: Int = 0
    @State private var batExpression: BatExpression = .default
    @State private var expressionIndex = 0

    private let totalSegments = 20
    private let expressions: [BatExpression] = [.default, .winking, .cheeky, .sleeping]

    init(title: String = "LOADING", message: String? = nil) {
        self.title = title
        self.message = message
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text(title)
                .font(CBFont.heading)
                .foregroundStyle(CBColor.textPrimary)

            if let message {
                Spacer().frame(height: 12)

                Text(message)
                    .font(CBFont.smallLabel)
                    .foregroundStyle(CBColor.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            Spacer().frame(height: 24)

            // Progress bar with segments filling one by one
            VStack(spacing: 6) {
                HStack(spacing: 1) {
                    ForEach(0..<totalSegments, id: \.self) { index in
                        Rectangle()
                            .fill(index < filledSegments ? CBColor.accent : CBColor.elevated.opacity(0.3))
                            .frame(width: 12, height: 16)
                    }
                }
                .padding(3)
                .background(CBColor.base)
                .overlay(
                    Rectangle()
                        .stroke(CBColor.borderStrong, lineWidth: 3)
                )

                Text("\(filledSegments * 5)")
                    .font(CBFont.pixelFont(size: 10))
                    .foregroundStyle(CBColor.textMuted)
            }

            Spacer().frame(height: 32)

            PixelBatView(
                expression: batExpression,
                pixelSize: 4,
                color: CBColor.accent
            )

            Spacer()
        }
        .padding(.horizontal, CBSpacing.popupPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CBColor.base)
        .onAppear {
            startAnimations()
        }
    }

    private func startAnimations() {
        // Fill segments one by one: 80ms per segment, 1600ms total, then loop
        Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
            filledSegments += 1
            if filledSegments > totalSegments {
                filledSegments = 0
            }
        }

        // Cycle bat expressions
        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            expressionIndex = (expressionIndex + 1) % expressions.count
            batExpression = expressions[expressionIndex]
        }
    }
}
