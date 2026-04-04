import SwiftUI

/// The menu bar label: number + segmented battery + cap
public struct MenuBarLabel: View {
    let viewModel: UsageViewModel

    public init(viewModel: UsageViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 4) {
            if let usage = viewModel.usage {
                Text("\(usage.fiveHour.remainingInt)")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.primary)
                    .fixedSize()

                MenuBarBattery(percentage: usage.fiveHour.remaining)
            } else {
                PixelBatView(expression: .dead, pixelSize: 1, color: CBColor.accent)
            }
        }
    }
}
