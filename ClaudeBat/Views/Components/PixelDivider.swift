import SwiftUI

/// Pixel dashed divider: alternating 4x2px filled/empty blocks
struct PixelDivider: View {
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<35, id: \.self) { index in
                if index.isMultiple(of: 2) {
                    Rectangle()
                        .fill(CBColor.borderStrong)
                        .frame(width: 4, height: 2)
                } else {
                    Color.clear
                        .frame(width: 4, height: 2)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
