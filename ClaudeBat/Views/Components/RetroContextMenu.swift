import SwiftUI

public struct RetroContextMenu: View {
    var onToggleLaunchAtLogin: () -> Void
    var onAbout: () -> Void
    var onQuit: () -> Void
    var launchAtLogin: Bool

    public init(onToggleLaunchAtLogin: @escaping () -> Void, onAbout: @escaping () -> Void, onQuit: @escaping () -> Void, launchAtLogin: Bool) {
        self.onToggleLaunchAtLogin = onToggleLaunchAtLogin
        self.onAbout = onAbout
        self.onQuit = onQuit
        self.launchAtLogin = launchAtLogin
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            menuRow("Launch at Login", trailing: launchAtLogin ? "✓" : nil, trailingIsAccent: true, action: onToggleLaunchAtLogin)

            Divider().opacity(0.2).padding(.vertical, 4)

            menuRow("About", action: onAbout)
            menuRow("Quit", trailing: "⌘Q", muted: true, action: onQuit)
        }
        .padding(8)
        .background(CBColor.surface)
    }

    @ViewBuilder
    private func menuRow(
        _ title: String,
        trailing: String? = nil,
        trailingIsAccent: Bool = false,
        muted: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(muted ? CBColor.textMuted : CBColor.textPrimary)

                Spacer()

                if let trailing {
                    Text(trailing)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(trailingIsAccent ? CBColor.accent : CBColor.textMuted)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
