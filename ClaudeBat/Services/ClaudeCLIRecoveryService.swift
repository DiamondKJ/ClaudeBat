import Foundation

public struct ClaudeCLIRecoveryService: ClaudeCLIRecovering {
    private let shellPath: String
    private let claudeCommand: String

    public init(shellPath: String = "/bin/zsh", claudeCommand: String = "claude") {
        self.shellPath = shellPath
        self.claudeCommand = claudeCommand
    }

    public func recoverAuth(
        baselineFingerprint: String?,
        baselineExpiresAt: Int64?,
        tokenProvider: any TokenProvider,
        timeout: TimeInterval = 20
    ) async -> ClaudeCLIRecoveryResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        process.arguments = ["-q", "/dev/null", shellPath, "-lc", claudeCommand]
        process.standardInput = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return .launchFailed(error.localizedDescription)
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
}
