import SwiftUI

struct GameOverView: View {
    let usage: UsageResponse

    @State private var blinkVisible = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { _ in
            content
        }
    }

    private var content: some View {
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
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    blinkVisible.toggle()
                }
            }
        }
    }

    private var countdownText: String {
        guard let date = usage.fiveHour.resetsAtDate else { return "--:--" }
        let interval = date.timeIntervalSince(Date())
        guard interval > 0 else { return "0:00" }

        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    private var resetTimeShort: String {
        guard let date = usage.fiveHour.resetsAtDate else { return "--:--" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date).uppercased()
    }
}
