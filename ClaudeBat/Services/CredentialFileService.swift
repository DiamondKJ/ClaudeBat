import Foundation

/// Reads and writes Claude Code's OAuth credentials from `~/.claude/.credentials.json`.
///
/// Claude Code migrated off the macOS Keychain mid-2026; this file is now the live,
/// actively-rotated credential store. It holds the same JSON blob the Keychain entry
/// held (see `CredentialBlobCodec`) — plus an `mcpOAuth` section containing
/// third-party MCP server access tokens and client secrets that have nothing to do
/// with this app. Every write here is merge-preserving for that reason.
public struct CredentialFileService: TokenProvider {
    private let fileURL: URL
    private let fileManager: FileManager

    /// Default mode for a credentials file we create ourselves. An existing file's
    /// mode is preserved as-is rather than forced to this.
    private static let defaultPermissions: Int = 0o600

    public init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileURL = fileURL ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent(".credentials.json")
        self.fileManager = fileManager
    }

    // MARK: - Read

    public func readToken() -> String? {
        readOAuthSnapshot()?.accessToken
    }

    public func readOAuthSnapshot() -> OAuthCredentialSnapshot? {
        guard let json = readJSON() else { return nil }
        return CredentialBlobCodec.snapshot(fromJSONObject: json)
    }

    public func tokenFingerprint() -> String? {
        readOAuthSnapshot()?.fingerprint
    }

    public func credentialSource() -> CredentialSource? {
        readOAuthSnapshot() == nil ? nil : .credentialsFile
    }

    /// Whether the file exists at all, independent of whether it holds a usable
    /// credential. `CredentialStore` uses this to decide where a write should land
    /// when no source currently resolves — this app must never *create* Claude
    /// Code's credentials file, only update one Claude Code already owns.
    public var storeExists: Bool {
        fileManager.fileExists(atPath: resolvedURL.path)
    }

    public func credentialProbeSummary() -> String {
        "\(CredentialSource.credentialsFile.rawValue)=\(storeExists ? "present" : "absent")"
    }

    // MARK: - Write

    /// Merges `snapshot` into the existing file and replaces it atomically.
    ///
    /// Returns false — writing nothing — rather than risk the file whenever the
    /// situation is not clearly safe. Corrupting this file logs the user out of
    /// Claude Code *and* every MCP server they have connected, so a refused write
    /// (which `OAuthRefreshService` escalates into the normal recovery ladder) is
    /// always the better failure.
    @discardableResult
    public func writeOAuthSnapshot(_ snapshot: OAuthCredentialSnapshot) -> Bool {
        let destination = resolvedURL
        let directory = destination.deletingLastPathComponent()

        // Never create Claude Code's directory — if it isn't there, this machine
        // isn't using the file store and we have no business inventing one.
        guard fileManager.fileExists(atPath: directory.path) else { return false }

        let existingData = fileManager.contents(atPath: destination.path)
        let root: [String: Any]
        if let existingData {
            // Present but unparseable: bail. Never clobber a credentials file we
            // cannot read, because we cannot know what we would be destroying.
            guard let parsed = CredentialBlobCodec.jsonObject(fromData: existingData) else {
                return false
            }
            root = parsed
        } else {
            root = [:]
        }

        let merged = CredentialBlobCodec.merged(snapshot, into: root)
        guard let payload = CredentialBlobCodec.serialize(merged) else { return false }

        let mode = existingPermissions(of: destination) ?? Self.defaultPermissions
        guard replaceAtomically(destination: destination, with: payload, mode: mode) else {
            return false
        }

        return verifyWrite(of: snapshot, at: destination)
    }

    // MARK: - Private

    /// Dotfile managers routinely symlink `~/.claude`. Resolve first so the atomic
    /// replace lands on the real file instead of turning the symlink into a regular
    /// file (which would silently detach the user's managed config).
    private var resolvedURL: URL {
        fileURL.resolvingSymlinksInPath()
    }

    private func readJSON() -> [String: Any]? {
        guard let data = fileManager.contents(atPath: resolvedURL.path) else { return nil }
        return CredentialBlobCodec.jsonObject(fromData: data)
    }

    private func existingPermissions(of url: URL) -> Int? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let permissions = attributes[.posixPermissions] as? NSNumber else {
            return nil
        }
        return permissions.intValue
    }

    /// Writes to a temp file in the *same directory*, then `rename(2)`s it over the
    /// destination.
    ///
    /// Two things here are load-bearing and easy to "simplify" into a bug:
    ///
    /// 1. **Do not replace this with `Data.write(to:options: .atomic)`.** That also
    ///    does temp-then-rename, but the temp file's mode comes from the umask —
    ///    typically `0644`. It would silently make the user's OAuth refresh token
    ///    world-readable. The temp file is created here with an explicit mode so the
    ///    plaintext secret is never even briefly readable by other users.
    /// 2. **Do not open the destination for an in-place truncating write.** A crash
    ///    mid-write would leave a truncated file, logging the user out of Claude Code
    ///    and every MCP server.
    ///
    /// `rename(2)` is atomic within a filesystem, and the surviving inode is the
    /// temp's — so it carries the mode set below, not the destination's.
    private func replaceAtomically(destination: URL, with payload: Data, mode: Int) -> Bool {
        let temporary = destination
            .deletingLastPathComponent()
            .appendingPathComponent("\(destination.lastPathComponent).claudebat-\(UUID().uuidString).tmp")

        var renamed = false
        defer {
            if !renamed { try? fileManager.removeItem(at: temporary) }
        }

        guard fileManager.createFile(
            atPath: temporary.path,
            contents: payload,
            attributes: [.posixPermissions: NSNumber(value: mode)]
        ) else {
            return false
        }

        // Belt and braces: createFile's attributes are honoured on Darwin, but an
        // unreadable-mode failure here is a security bug, not a cosmetic one.
        guard (try? fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: mode)],
            ofItemAtPath: temporary.path
        )) != nil,
            existingPermissions(of: temporary) == mode else {
            return false
        }

        guard rename(temporary.path, destination.path) == 0 else { return false }
        renamed = true
        return true
    }

    /// Confirms the credential actually landed.
    ///
    /// Treats "the file now holds a *newer* credential than ours" as success:
    /// Claude Code won a concurrent write with something fresher, which satisfies
    /// the goal. Reporting failure there would spuriously escalate into the hidden
    /// Claude CLI relaunch.
    private func verifyWrite(of snapshot: OAuthCredentialSnapshot, at destination: URL) -> Bool {
        guard let current = readOAuthSnapshot() else { return false }
        if current.accessToken == snapshot.accessToken { return true }

        guard let currentExpiry = current.expiresAt, let writtenExpiry = snapshot.expiresAt else {
            return false
        }
        return currentExpiry > writtenExpiry
    }
}
