import SwiftUI

/// 20x20 pixel X close button with 2x2px blocks
struct PixelCloseButton: View {
    var action: () -> Void

    // Pixel positions for the X pattern (2x2 blocks)
    private let pixels: [(Int, Int)] = [
        // Top-left to center
        (3, 3), (5, 3), (13, 3), (15, 3),
        (3, 5), (5, 5), (7, 5), (11, 5), (13, 5), (15, 5),
        (5, 7), (7, 7), (9, 7), (11, 7), (13, 7),
        // Center
        (7, 9), (9, 9), (11, 9),
        // Center to bottom-left
        (5, 11), (7, 11), (9, 11), (11, 11), (13, 11),
        (3, 13), (5, 13), (7, 13), (11, 13), (13, 13), (15, 13),
        (3, 15), (5, 15), (13, 15), (15, 15),
    ]

    var body: some View {
        Button(action: action) {
            Canvas { context, _ in
                for (x, y) in pixels {
                    let rect = CGRect(x: x, y: y, width: 2, height: 2)
                    context.fill(Path(rect), with: .color(CBColor.textSecondary))
                }
            }
            .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}
