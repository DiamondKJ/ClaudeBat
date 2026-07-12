import Foundation

public struct ClaudeCLIRecoveryService: ClaudeCLIRecovering {
    private let claudeCommand: String

    public init(claudeCommand: String = "claude") {
        self.claudeCommand = claudeCommand
    }

    public func recoverAuth(
        baselineFingerprint: String?,
        baselineExpiresAt: Int64?,
        tokenProvider: any TokenProvider,
        timeout: TimeInterval = 20
    ) async -> ClaudeCLIRecoveryResult {
        guard let claudeExecutable = Self.resolveExecutable(named: claudeCommand) else {
            return .launchFailed("Claude CLI executable not found")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        process.arguments = ["-q", "/dev/null", claudeExecutable]
        process.standardInput = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return .launchFailed("failed to launch Claude CLI")
        }

        let deadline = Date().addingTimeInterval(timeout)
        defer {
            if process.isRunning {
                process.terminate()
                let pid = process.processIdentifier
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    if process.isRunning {
                        kill(pid, SIGKILL)
                    }
                }
            }
        }

        while Date() < deadline {
            if Task.isCancelled {
                return .timedOut
            }

            let latestSnapshot = tokenProvider.readOAuthSnapshot()
            let latestFingerprint = latestSnapshot?.fingerprint
            let latestExpiresAt = latestSnapshot?.expiresAt

            if latestFingerprint != nil, latestFingerprint != baselineFingerprint {
                return .success
            }

            if latestExpiresAt != nil, latestExpiresAt != baselineExpiresAt {
                return .success
            }

            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        return .timedOut
    }

    private static func resolveExecutable(named command: String) -> String? {
        if command.contains("/") {
            return isTrustedExecutable(command) ? command : nil
        }

        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        // Fixed locations first — a Finder-launched .app inherits a minimal
        // PATH, so common user-local install dirs must be searched explicitly.
        let home = NSHomeDirectory()
        let fixedDirectories = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.claude/local",
            "\(home)/.npm-global/bin",
            "\(home)/.local/bin",
        ]

        for directory in fixedDirectories + pathEntries {
            let candidate = URL(fileURLWithPath: directory)
                .appendingPathComponent(command)
                .path
            if isTrustedExecutable(candidate) {
                return candidate
            }
        }

        return nil
    }

    /// This binary runs invisibly with the user's full privileges, so a planted
    /// executable must not qualify: require ownership by root or the current
    /// user, and reject anything group- or world-writable.
    private static func isTrustedExecutable(_ path: String) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: path) else { return false }
        var info = stat()
        guard stat(path, &info) == 0 else { return false }
        guard info.st_uid == getuid() || info.st_uid == 0 else { return false }
        return (info.st_mode & (mode_t(S_IWGRP) | mode_t(S_IWOTH))) == 0
    }
}
