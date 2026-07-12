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
        // Subscripting with a nil optional REMOVES the key — this is Claude
        // Code's credential blob, so a partial snapshot must never strip
        // fields it doesn't have values for.
        oauth["accessToken"] = snapshot.accessToken
        if let refreshToken = snapshot.refreshToken { oauth["refreshToken"] = refreshToken }
        if let expiresAt = snapshot.expiresAt { oauth["expiresAt"] = expiresAt }
        if !snapshot.scopes.isEmpty { oauth["scopes"] = snapshot.scopes }
        if let subscriptionType = snapshot.subscriptionType { oauth["subscriptionType"] = subscriptionType }
        if let rateLimitTier = snapshot.rateLimitTier { oauth["rateLimitTier"] = rateLimitTier }
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

    /// Writes via `security -i` with the command supplied on stdin. Passing the
    /// credential payload as a `-w` argv argument would expose it to any
    /// same-user process via `ps` for the lifetime of the subprocess; stdin is
    /// private to this pipe. `security -i` tokenizes double-quoted strings with
    /// backslash escapes and exits nonzero when the command fails (verified
    /// empirically — a failed delete exits 44).
    private static func writeSecurityCommand(payload: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["-i"]

        let stdinPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let command = [
            "add-generic-password",
            "-U",
            "-a", quoted(NSUserName()),
            "-s", quoted(serviceName),
            "-w", quoted(payload),
        ].joined(separator: " ") + "\n"

        do {
            try process.run()
            stdinPipe.fileHandleForWriting.write(Data(command.utf8))
            stdinPipe.fileHandleForWriting.closeFile()
            process.waitUntilExit()
        } catch {
            return false
        }

        return process.terminationStatus == 0
    }

    private static func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
