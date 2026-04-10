import Foundation

public struct KeychainService: TokenProvider {
    private static let serviceName = "Claude Code-credentials"

    public init() {}

    /// Read the OAuth token from macOS Keychain via /usr/bin/security subprocess.
    /// This bypasses SecItemCopyMatching ACL issues — the security binary is always
    /// in the Keychain partition list because Claude Code uses it to create the entry.
    /// Result: zero prompts, ever.
    public func readToken() -> String? {
        readOAuthSnapshot()?.accessToken
    }

    public func readOAuthSnapshot() -> OAuthCredentialSnapshot? {
        guard let raw = Self.runSecurityCommand() else { return nil }

        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return token.isEmpty ? nil : OAuthCredentialSnapshot(accessToken: token)
        }

        if let oauth = json["claudeAiOauth"] as? [String: Any],
           let token = oauth["accessToken"] as? String {
            let expiresAt: Int64?
            if let number = oauth["expiresAt"] as? NSNumber {
                expiresAt = number.int64Value
            } else if let string = oauth["expiresAt"] as? String, let value = Int64(string) {
                expiresAt = value
            } else {
                expiresAt = nil
            }

            let scopes: [String]
            if let scopeString = oauth["scopes"] as? String {
                scopes = scopeString.split(separator: " ").map(String.init)
            } else if let scopeArray = oauth["scopes"] as? [String] {
                scopes = scopeArray
            } else {
                scopes = []
            }

            return OAuthCredentialSnapshot(
                accessToken: token,
                refreshToken: oauth["refreshToken"] as? String,
                expiresAt: expiresAt,
                scopes: scopes,
                subscriptionType: oauth["subscriptionType"] as? String,
                rateLimitTier: oauth["rateLimitTier"] as? String
            )
        }

        if let token = json["access_token"] as? String {
            return OAuthCredentialSnapshot(accessToken: token)
        }

        return nil
    }

    @discardableResult
    public func writeOAuthSnapshot(_ snapshot: OAuthCredentialSnapshot) -> Bool {
        var root = Self.readRawJSON() ?? [:]
        var oauth = (root["claudeAiOauth"] as? [String: Any]) ?? [:]
        oauth["accessToken"] = snapshot.accessToken
        oauth["refreshToken"] = snapshot.refreshToken
        oauth["expiresAt"] = snapshot.expiresAt
        oauth["scopes"] = snapshot.scopes
        oauth["subscriptionType"] = snapshot.subscriptionType
        oauth["rateLimitTier"] = snapshot.rateLimitTier
        root["claudeAiOauth"] = oauth

        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]),
              let payload = String(data: data, encoding: .utf8) else {
            return false
        }

        return Self.writeSecurityCommand(payload: payload)
    }

    public func tokenFingerprint() -> String? {
        readOAuthSnapshot()?.fingerprint
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

    private static func readRawJSON() -> [String: Any]? {
        guard let raw = runSecurityCommand(),
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return json
    }

    private static func writeSecurityCommand(payload: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "add-generic-password",
            "-U",
            "-a", NSUserName(),
            "-s", serviceName,
            "-w", payload,
        ]

        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }

        return process.terminationStatus == 0
    }
}
