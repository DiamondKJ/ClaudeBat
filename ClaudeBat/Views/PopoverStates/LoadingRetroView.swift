import SwiftUI

struct LoadingRetroView: View {
    let title: String
    let message: String?
    @Environment(\.popoverDisplayEnvironment) private var displayEnvironment

    private let totalSegments = 20
    private let expressions: [BatExpression] = [.default, .winking, .cheeky, .sleeping]

    init(title: String = "LOADING", message: String? = nil) {
        self.title = title
        self.message = message
    }

    var body: some View {
        Group {
            if let fixedNow = displayEnvironment.fixedNow {
                content(at: fixedNow)
            } else {
                TimelineView(.periodic(from: .now, by: 0.08)) { context in
                    content(at: context.date)
                }
            }
        }
    }

    private func content(at date: Date) -> some View {
        let filledSegments = filledSegmentCount(at: date)
        return VStack(spacing: 0) {
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
                    expression: expression(at: date),
                    pixelSize: 4,
                    color: CBColor.accent
                )

                Spacer()
            }
            .padding(.horizontal, CBSpacing.popupPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CBColor.base)
    }

    private func filledSegmentCount(at date: Date) -> Int {
        Int(date.timeIntervalSinceReferenceDate / 0.08) % (totalSegments + 1)
    }

    private func expression(at date: Date) -> BatExpression {
        let index = Int(date.timeIntervalSinceReferenceDate / 1.5) % expressions.count
        return expressions[index]
    }
}
