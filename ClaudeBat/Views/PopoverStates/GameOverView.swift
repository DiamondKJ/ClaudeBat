import SwiftUI

struct GameOverView: View {
    let usage: UsageResponse

    @Environment(\.openURL) private var openURL
    @Environment(\.popoverDisplayEnvironment) private var displayEnvironment

    var body: some View {
        Group {
            if let fixedNow = displayEnvironment.fixedNow {
                content(blinkVisible: blinkVisible(at: fixedNow))
            } else {
                TimelineView(.periodic(from: .now, by: 0.8)) { context in
                    content(blinkVisible: blinkVisible(at: context.date))
                }
            }
        }
    }

    private func content(blinkVisible: Bool) -> some View {
        VStack(spacing: 0) {
            Spacer()

            // Dead bat
            PixelBatView(expression: .dead, pixelSize: 3, color: CBColor.batteryCritical)

            Spacer().frame(height: 16)

            // GAME OVER
            Text("GAME OVER")
                .font(CBFont.pixelFont(size: 16))
                .foregroundStyle(CBColor.batteryCritical)

            Spacer().frame(height: 20)

            // The countdown — THE hero element
            Text(countdownText)
                .font(CBFont.displayNumber)
                .foregroundStyle(CBColor.accent)

            Spacer().frame(height: 24)

            // CONTINUE AT [TIME]
            Text("CONTINUE AT \(resetTimeShort)")
                .font(CBFont.pixelFont(size: 12))
                .foregroundStyle(CBColor.textPrimary)
                .opacity(blinkVisible ? 1 : 0.3)

            Spacer().frame(height: 24)

            // Escape hatch — a blocked user's one actionable next step. No API call.
            Button {
                openURL(CBLinks.manageUsage)
            } label: {
                Text("MANAGE USAGE")
                    .font(CBFont.pixelFont(size: 10))
                    .foregroundStyle(CBColor.base)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(CBColor.accent)
                    .clipShape(RoundedRectangle(cornerRadius: CBRadius.button))
            }
            .buttonStyle(.plain)

            if let extra = usage.extraUsage, extra.isEnabled {
                Spacer().frame(height: 16)
                Text("Extra usage: \(extra.usedFormatted)\(extra.monthlyLimit != nil ? " / \(extra.limitFormatted)" : "")")
                    .font(CBFont.smallLabel)
                    .foregroundStyle(CBColor.accent)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    /// The reset we're actually waiting on: the latest reset among the exhausted
    /// limits. If weekly is maxed you're blocked until it resets even after the
    /// 5-hour window clears, so the countdown must track the furthest-out one.
    private var blockingResetDate: Date? {
        var dates: [Date] = []
        if usage.fiveHour.remaining <= 0, let d = usage.fiveHour.resetsAtDate { dates.append(d) }
        if usage.sevenDay.remaining <= 0, let d = usage.sevenDay.resetsAtDate { dates.append(d) }
        return dates.max() ?? usage.fiveHour.resetsAtDate
    }

    private var countdownText: String {
        guard let date = blockingResetDate else { return "--:--" }
        let interval = date.timeIntervalSince(displayEnvironment.now)
        guard interval > 0 else { return "0:00" }

        let totalMinutes = Int(interval) / 60
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes % (60 * 24)) / 60
        let minutes = totalMinutes % 60

        if days > 0 { return "\(days)d \(hours)h" }
        return "\(hours)h \(minutes)m"
    }

    private var resetTimeShort: String {
        guard let date = blockingResetDate else { return "--:--" }
        // Shared formatter: dated for far-off (weekly) resets, time-only for same-day.
        return UsagePeriod.formatResetTimestamp(
            date,
            reference: displayEnvironment.now,
            timeZone: displayEnvironment.timeZone
        ).uppercased()
    }

    private func blinkVisible(at date: Date) -> Bool {
        Int(date.timeIntervalSinceReferenceDate / 0.8) % 2 == 0
    }
}
