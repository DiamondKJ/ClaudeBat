import SwiftUI

/// Model breakdown row: number + mini bar + label
/// Mirrors weekly layout: number on left, bar in middle, label on right.
struct ModelBreakdownRow: View {
    let label: String
    let remaining: Double
    var isMaxed: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Text(isMaxed ? "" : "\(Int(remaining.rounded()))")
                .font(CBFont.modelNumber)
                .foregroundStyle(CBColor.textPrimary)
                .frame(width: 50, alignment: .leading)

            SegmentedBatteryBar(
                percentage: remaining,
                size: .mini,
                fillColor: isMaxed ? CBColor.batteryCritical : CBColor.accent
            )

            Text(label)
                .font(CBFont.modelLabel)
                .foregroundStyle(isMaxed ? CBColor.batteryCritical : CBColor.textPrimary)
                .fixedSize()
                .frame(width: 50, alignment: .trailing)
        }
    }
}
