import SwiftUI

struct NormalUsageView: View {
    let usage: UsageResponse
    @Environment(\.popoverDisplayEnvironment) private var displayEnvironment

    var body: some View {
        Group {
            if displayEnvironment.fixedNow != nil {
                content
            } else {
                // TimelineView ticks every 60s so countdowns stay live
                TimelineView(.periodic(from: .now, by: 60.0)) { _ in
                    content
                }
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            // Session section
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(
                    title: "SESSION",
                    subtitle: usage.fiveHour.timeUntilReset(
                        reference: displayEnvironment.now,
                        timeZone: displayEnvironment.timeZone
                    )
                )

                // Big number + "left"
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text("\(usage.fiveHour.remainingInt)")
                        .font(CBFont.pixelFont(size: 40))
                        .foregroundStyle(sessionNumberColor)
                        .lineLimit(1)

                    Text("left")
                        .font(CBFont.bodyText)
                        .foregroundStyle(
                            usage.fiveHour.remaining <= 0
                                ? CBColor.batteryCritical
                                : CBColor.textMuted
                        )
                }

                // Session battery bar — color changes with percentage
                SegmentedBatteryBar(
                    percentage: usage.fiveHour.remaining,
                    size: .default,
                    borderColor: usage.fiveHour.remaining <= 0 ? CBColor.batteryCritical : nil
                )

                if usage.fiveHour.remaining <= 0 {
                    Text("Session limit reached")
                        .font(CBFont.pixelFont(size: 9))
                        .foregroundStyle(CBColor.batteryCritical)
                }
            }

            Spacer().frame(height: 20)
            PixelDivider()
            Spacer().frame(height: 20)

            // Weekly section
            VStack(alignment: .leading, spacing: CBPopoverMetrics.lowerSectionSpacing) {
                SectionHeader(
                    title: "THIS WEEK",
                    subtitle: usage.sevenDay.resetDateShort(
                        reference: displayEnvironment.now,
                        timeZone: displayEnvironment.timeZone
                    )
                )

                WeeklyUsageRow(period: usage.sevenDay)
            }

            // Model breakdown — one row per model-scoped weekly limit (Fable,
            // Sonnet, ...), sourced from the API's `limits` array with legacy
            // seven_day_sonnet/opus fallback. Absent data must NOT coalesce to 0
            // (that paints a fake red "maxed" row identical to a genuinely
            // exhausted tier).
            let modelBreakdown = usage.weeklyModelBreakdown
            if !modelBreakdown.isEmpty {
                Spacer().frame(height: CBPopoverMetrics.lowerSectionSpacing)

                VStack(spacing: CBPopoverMetrics.modelRowSpacing) {
                    ForEach(modelBreakdown) { entry in
                        ModelBreakdownRow(
                            label: entry.label,
                            remaining: entry.period.remaining,
                            isMaxed: entry.period.remaining <= 0
                        )
                    }
                }
            }

            // Extra usage section — only when enabled
            if let extra = usage.extraUsage, extra.isEnabled {
                Spacer().frame(height: 16)
                PixelDivider()
                Spacer().frame(height: 16)

                VStack(spacing: 4) {
                    HStack {
                        Text("EXTRA USAGE")
                            .font(CBFont.sectionHeader)
                            .foregroundStyle(CBColor.textMuted)
                            .tracking(0.6)

                        Spacer()

                        Text("Enabled")
                            .font(CBFont.tinyLabel)
                            .foregroundStyle(CBColor.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(CBColor.accent.opacity(0.3), lineWidth: 1)
                            )
                    }

                    let spendText = extra.monthlyLimit != nil
                        ? "\(extra.usedFormatted) / \(extra.limitFormatted) this month"
                        : "\(extra.usedFormatted) this month"
                    Text(spendText)
                        .font(CBFont.modelLabel)
                        .foregroundStyle(CBColor.textMuted)
                }
            }

        }
    }

    private var sessionNumberColor: Color {
        if usage.fiveHour.remaining <= 0 { return CBColor.batteryCritical }
        return CBColor.textPrimary
    }
}
