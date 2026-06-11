import SwiftUI

/// The menu bar label: number + segmented battery + cap
@MainActor
public struct MenuBarLabel: View {
    let viewModel: UsageViewModel
    /// Called when the per-state tooltip text changes, so the host can set it on
    /// the NSStatusBarButton (which lives outside SwiftUI).
    var onTooltipChange: ((String) -> Void)?

    public init(viewModel: UsageViewModel, onTooltipChange: ((String) -> Void)? = nil) {
        self.viewModel = viewModel
        self.onTooltipChange = onTooltipChange
    }

    public var body: some View {
        content
            .onAppear { onTooltipChange?(viewModel.menuBarTooltip) }
            .onChange(of: viewModel.menuBarTooltip) { _, newValue in
                onTooltipChange?(newValue)
            }
    }

    private var content: some View {
        HStack(spacing: 4) {
            if let usage = viewModel.usage, viewModel.shouldShowMenuBarUsage {
                if viewModel.isDepleted {
                    // Cooked — either the session or the weekly limit is exhausted, so
                    // you can't actually use Claude. Drop to the red dead bat to match
                    // the GAME OVER popover instead of showing a misleading number.
                    PixelBatView(expression: .dead, pixelSize: 1, color: CBColor.batteryCritical)
                } else {
                    Text("\(usage.fiveHour.remainingInt)")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.primary)
                        .fixedSize()

                    MenuBarBattery(percentage: usage.fiveHour.remaining)
                }
            } else {
                PixelBatView(
                    expression: viewModel.sessionDataNeedsRefresh ? .sleeping : .dead,
                    pixelSize: 1,
                    color: CBColor.accent
                )
            }
        }
    }
}
