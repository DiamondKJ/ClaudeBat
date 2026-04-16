import SwiftUI
import AppKit

struct NoAuthView: View {
    enum Mode {
        case setup
        case reconnect
    }

    var mode: Mode = .setup
    var forceInstalled: Bool? = nil

    private var claudeCodeInstalled: Bool {
        if let forced = forceInstalled { return forced }
        return FileManager.default.fileExists(atPath: "/usr/local/bin/claude")
            || FileManager.default.fileExists(atPath: "/opt/homebrew/bin/claude")
            || executableOnPath(named: "claude")
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Pixel padlock icon
            PixelPadlock()

            Spacer().frame(height: 16)

            // Title
            Text(title)
                .font(CBFont.pixelFont(size: 16))
                .foregroundStyle(CBColor.textPrimary)

            Spacer().frame(height: 16)

            Text(summary)
                .font(CBFont.modelLabel)
                .foregroundStyle(CBColor.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            Spacer().frame(height: 16)

            if claudeCodeInstalled {
                Text(primaryInstruction)
                    .font(CBFont.modelLabel)
                    .foregroundStyle(CBColor.textMuted)

                Spacer().frame(height: 12)

                TerminalBlock(command: "claude")
            } else {
                Text("Install Claude Code first:")
                    .font(CBFont.modelLabel)
                    .foregroundStyle(CBColor.textMuted)

                Spacer().frame(height: 12)

                TerminalBlock(command: "npm i -g @anthropic-ai/claude-code")

                Spacer().frame(height: 12)

                Text("Then log in:")
                    .font(CBFont.modelLabel)
                    .foregroundStyle(CBColor.textMuted)

                Spacer().frame(height: 8)

                TerminalBlock(command: "claude")
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, CBSpacing.popupPadding)
    }

    private func executableOnPath(named command: String) -> Bool {
        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        for directory in pathEntries {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(command).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return true
            }
        }

        return false
    }

    private var title: String {
        switch mode {
        case .setup:
            return "No Token Found"
        case .reconnect:
            return "Reconnect Claude"
        }
    }

    private var summary: String {
        switch mode {
        case .setup:
            return "ClaudeBat needs your Claude Code login before it can read usage."
        case .reconnect:
            return "ClaudeBat needs a fresh Claude Code login before it can refresh usage."
        }
    }

    private var primaryInstruction: String {
        switch mode {
        case .setup:
            return "Log in to Claude Code:"
        case .reconnect:
            return "Refresh your Claude Code login:"
        }
    }
}

// MARK: - Terminal Block with Copy

private struct TerminalBlock: View {
    let command: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title bar: traffic lights + copy button
            HStack(spacing: 4) {
                Circle().fill(CBColor.batteryCritical).frame(width: 6, height: 6)
                Circle().fill(CBColor.batteryMid).frame(width: 6, height: 6)
                Circle().fill(CBColor.batteryHigh).frame(width: 6, height: 6)

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied = false
                    }
                } label: {
                    Text(copied ? "Copied!" : "Copy")
                        .font(CBFont.tinyLabel)
                        .foregroundStyle(copied ? CBColor.batteryHigh : CBColor.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 8)

            // Command
            HStack(alignment: .top, spacing: 6) {
                Text("$")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(CBColor.textMuted)
                Text(command)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(CBColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CBColor.base)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Pixel Padlock Icon

private struct PixelPadlock: View {
    private let color = CBColor.batteryMid // Amber

    private let pixels: [(Int, Int)] = [
        (3,0), (4,0), (5,0),
        (2,1), (6,1),
        (2,2), (6,2),
        (1,3), (2,3), (3,3), (4,3), (5,3), (6,3), (7,3),
        (1,4), (2,4), (3,4), (4,4), (5,4), (6,4), (7,4),
        (1,5), (2,5), (3,5), (4,5), (5,5), (6,5), (7,5),
        (1,6), (2,6), (3,6), (4,6), (5,6), (6,6), (7,6),
        (1,7), (2,7), (3,7), (4,7), (5,7), (6,7), (7,7),
        (1,8), (2,8), (3,8), (4,8), (5,8), (6,8), (7,8),
    ]

    private let keyhole: [(Int, Int)] = [
        (4,5),
        (3,6), (4,6), (5,6),
        (4,7),
    ]

    var body: some View {
        Canvas { context, _ in
            let size: CGFloat = 5
            for (x, y) in pixels {
                let rect = CGRect(x: CGFloat(x) * size, y: CGFloat(y) * size, width: size, height: size)
                context.fill(Path(rect), with: .color(color))
            }
            for (x, y) in keyhole {
                let rect = CGRect(x: CGFloat(x) * size, y: CGFloat(y) * size, width: size, height: size)
                context.fill(Path(rect), with: .color(CBColor.base))
            }
        }
        .frame(width: 8 * 5, height: 9 * 5)
    }
}
