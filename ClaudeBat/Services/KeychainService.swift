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
        return CredentialBlobCodec.snapshot(fromRawString: raw)
    }

    @discardableResult
    public func writeOAuthSnapshot(_ snapshot: OAuthCredentialSnapshot) -> Bool {
        let root = CredentialBlobCodec.merged(snapshot, into: Self.readRawJSON() ?? [:])

        guard let data = CredentialBlobCodec.serialize(root),
              let payload = String(data: data, encoding: .utf8) else {
            return false
        }

        return Self.writeSecurityCommand(payload: payload)
    }

    public func tokenFingerprint() -> String? {
        readOAuthSnapshot()?.fingerprint
    }

    public func credentialSource() -> CredentialSource? {
        readOAuthSnapshot() == nil ? nil : .keychain
    }

    /// Whether the backing store exists at all, independent of whether it holds a
    /// usable credential. `CredentialStore` uses this to decide where a write
    /// should land when no source currently resolves.
    public var storeExists: Bool {
        Self.runSecurityCommand() != nil
    }

    public func credentialProbeSummary() -> String {
        "\(CredentialSource.keychain.rawValue)=\(storeExists ? "present" : "absent")"
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
        guard let raw = runSecurityCommand() else { return nil }
        return CredentialBlobCodec.jsonObject(fromRawString: raw)
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
