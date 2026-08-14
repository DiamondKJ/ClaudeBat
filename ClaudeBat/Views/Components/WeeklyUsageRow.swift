import SwiftUI

/// Shared weekly summary row with a vertically fixed trailing balancer.
struct WeeklyUsageRow: View {
    let period: UsagePeriod

    var body: some View {
        HStack(spacing: 10) {
            Text("\(period.remainingInt)")
                .font(CBFont.weeklyNumber)
                .foregroundStyle(CBColor.textPrimary)
                .frame(width: 50, alignment: .leading)

            SegmentedBatteryBar(
                percentage: period.remaining,
                size: .medium
            )

            // Balance the leading number column without accepting surplus
            // vertical space from an oversized host proposal.
            Color.clear.frame(width: 50, height: 1)
        }
        .accessibilityIdentifier("weekly-usage-row")
    }
}
