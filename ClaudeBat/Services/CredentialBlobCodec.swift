import Foundation

/// Pure parse/merge/serialize for Claude Code's OAuth credential blob.
///
/// The Keychain item (`Claude Code-credentials`) and the credentials file
/// (`~/.claude/.credentials.json`) hold the *same* JSON shape, so both
/// `KeychainService` and `CredentialFileService` share this codec rather than
/// duplicating the field handling. No I/O happens here — that is deliberate,
/// it makes every parsing quirk below testable without a Keychain or a filesystem.
public enum CredentialBlobCodec {
    /// Parses the raw contents of a credential store.
    ///
    /// Falls back to treating non-JSON input as a bare access token, which is how
    /// a hand-created Keychain entry (`security add-generic-password -w <token>`)
    /// looks.
    public static func snapshot(fromRawString raw: String) -> OAuthCredentialSnapshot? {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return token.isEmpty ? nil : OAuthCredentialSnapshot(accessToken: token)
        }

        return snapshot(fromJSONObject: json)
    }

    /// Extracts the OAuth snapshot from a parsed credential blob.
    ///
    /// Both `expiresAt` encodings (number and string) and both `scopes` encodings
    /// (space-delimited string and array) occur in the wild across Claude Code
    /// versions, so all four are handled.
    public static func snapshot(fromJSONObject json: [String: Any]) -> OAuthCredentialSnapshot? {
        if let oauth = json[oauthKey] as? [String: Any],
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

    public static func jsonObject(fromRawString raw: String) -> [String: Any]? {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return json
    }

    public static func jsonObject(fromData data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Merges `snapshot` into an existing credential blob, preserving everything
    /// it doesn't own.
    ///
    /// This blob is Claude Code's, not ours. Beyond `claudeAiOauth` it carries an
    /// `mcpOAuth` section holding third-party MCP server tokens and client
    /// secrets, and `claudeAiOauth` itself carries fields we don't model (e.g.
    /// `refreshTokenExpiresAt`). Only the keys we have values for are touched.
    ///
    /// Note the asymmetry: `accessToken` is assigned unconditionally, every other
    /// field only when non-nil / non-empty. Subscripting with a nil optional
    /// REMOVES the key, so a partial snapshot must never strip fields it simply
    /// doesn't have values for.
    public static func merged(
        _ snapshot: OAuthCredentialSnapshot,
        into root: [String: Any]
    ) -> [String: Any] {
        var root = root
        var oauth = (root[oauthKey] as? [String: Any]) ?? [:]

        oauth["accessToken"] = snapshot.accessToken
        if let refreshToken = snapshot.refreshToken { oauth["refreshToken"] = refreshToken }
        if let expiresAt = snapshot.expiresAt { oauth["expiresAt"] = expiresAt }
        if !snapshot.scopes.isEmpty { oauth["scopes"] = snapshot.scopes }
        if let subscriptionType = snapshot.subscriptionType { oauth["subscriptionType"] = subscriptionType }
        if let rateLimitTier = snapshot.rateLimitTier { oauth["rateLimitTier"] = rateLimitTier }
        root[oauthKey] = oauth

        return root
    }

    public static func serialize(_ root: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    private static let oauthKey = "claudeAiOauth"
}
