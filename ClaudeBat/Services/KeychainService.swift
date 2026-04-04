import Foundation

public struct KeychainService: TokenProvider {
    private static let serviceName = "Claude Code-credentials"

    public init() {}

    /// Read the OAuth token from macOS Keychain via /usr/bin/security subprocess.
    /// This bypasses SecItemCopyMatching ACL issues — the security binary is always
    /// in the Keychain partition list because Claude Code uses it to create the entry.
    /// Result: zero prompts, ever.
    public func readToken() -> String? {
        guard let raw = Self.runSecurityCommand() else { return nil }

        // Claude Code stores: { "claudeAiOauth": { "accessToken": "..." } }
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let oauth = json["claudeAiOauth"] as? [String: Any],
           let token = oauth["accessToken"] as? String {
            return token
        }

        if let token = json["access_token"] as? String {
            return token
        }

        return nil
    }

    private static func runSecurityCommand() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", serviceName, "-w"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
