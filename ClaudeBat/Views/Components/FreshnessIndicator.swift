import SwiftUI

/// Freshness footnote: 6×6 pixel dot + age text.
/// Dot color shifts by age. Text stays muted always.
struct FreshnessIndicator: View {
    let fetchedAt: Date?
    var freshness: UsageViewModel.Freshness = .empty

    @State private var dotOpacity: Double = 1.0
    @Environment(\.popoverDisplayEnvironment) private var displayEnvironment

    var body: some View {
        Group {
            if displayEnvironment.fixedNow != nil {
                content
            } else {
                TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                    content
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if freshness == .refreshing {
            HStack(spacing: 4) {
                dotView(color: CBColor.batteryHigh)
                    .opacity(dotOpacity)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                            dotOpacity = 0.3
                        }
                    }
                    .onDisappear { dotOpacity = 1.0 }
                Text("Updating...")
                    .font(CBFont.smallLabel)
                    .foregroundStyle(CBColor.textMuted)
            }
        } else if let fetchedAt {
            let now = displayEnvironment.now
            HStack(spacing: 4) {
                dotView(color: dotColor(for: fetchedAt, now: now))
                Text(relativeTimestamp(from: fetchedAt, now: now))
                    .font(CBFont.smallLabel)
                    .foregroundStyle(CBColor.textMuted)
            }
        }
    }

    private func dotView(color: Color) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: 6, height: 6)
    }

    private func relativeTimestamp(from date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 1 { return "Just now" }
        if seconds < 60 { return "\(seconds)s" }
        let m = seconds / 60
        let s = seconds % 60
        if seconds < 3600 { return "\(m)m \(s)s" }
        let h = seconds / 3600
        return "\(h)h \(m % 60)m"
    }

    private func dotColor(for date: Date, now: Date) -> Color {
        let age = now.timeIntervalSince(date)
        if age < 120 { return CBColor.textMuted }
        if age < 600 { return CBColor.batteryMid }
        return CBColor.batteryLow
    }
}
