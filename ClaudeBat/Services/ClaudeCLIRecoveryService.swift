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
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    if process.isRunning {
                        process.interrupt()
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
            return FileManager.default.isExecutableFile(atPath: command) ? command : nil
        }

        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        for directory in ["/opt/homebrew/bin", "/usr/local/bin"] + pathEntries {
            let candidate = URL(fileURLWithPath: directory)
                .appendingPathComponent(command)
                .path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }
}
