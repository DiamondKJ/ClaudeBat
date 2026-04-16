import SwiftUI

/// Shared header for popup: bat icon + "ClaudeBat" + close button
/// Bat cycles through expressions: default → winking → cheeky → sleeping → loop
struct PopoverHeader: View {
    var onClose: (() -> Void)? = nil

    private let expressions: [BatExpression] = [.default, .winking, .cheeky, .sleeping]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2.0)) { context in
            HStack {
                HStack(spacing: 8) {
                    PixelBatView(expression: expression(at: context.date), pixelSize: 1.5, color: CBColor.accent)
                    Text("ClaudeBat")
                        .font(CBFont.pixelFont(size: 14))
                        .foregroundStyle(CBColor.accent)
                }

                Spacer()

                if let onClose {
                    PixelCloseButton(action: onClose)
                }
            }
        }
    }

    private func expression(at date: Date) -> BatExpression {
        let index = Int(date.timeIntervalSinceReferenceDate / 2.0) % expressions.count
        return expressions[index]
    }
}
