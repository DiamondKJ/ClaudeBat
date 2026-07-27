import Foundation

/// Resolves Claude Code's OAuth credentials across every store it might live in.
///
/// Claude Code moved from the macOS Keychain to `~/.claude/.credentials.json`
/// mid-2026. Both stores still exist in the wild — a machine that migrated may keep
/// a stale Keychain entry, and a user on an older Claude Code has only the Keychain
/// — so this composes both rather than picking one.
public struct CredentialStore: TokenProvider {
    private let sources: [any TokenProvider]
    private let expirySkew: TimeInterval
    private let now: @Sendable () -> Date

    public init(
        sources: [any TokenProvider] = [CredentialFileService(), KeychainService()],
        expirySkew: TimeInterval = 60,
        now: @Sendable @escaping () -> Date = { Date() }
    ) {
        self.sources = sources
        self.expirySkew = expirySkew
        self.now = now
    }

    // MARK: - Read

    public func readToken() -> String? {
        readOAuthSnapshot()?.accessToken
    }

    public func readOAuthSnapshot() -> OAuthCredentialSnapshot? {
        resolve()?.snapshot
    }

    public func tokenFingerprint() -> String? {
        readOAuthSnapshot()?.fingerprint
    }

    public func credentialSource() -> CredentialSource? {
        guard let resolved = resolve() else { return nil }
        return sources[resolved.index].credentialSource()
    }

    public var storeExists: Bool {
        sources.contains { $0.storeExists }
    }

    /// Which stores were probed and whether each one exists. Used for the
    /// `credential_source_unavailable` monitor event — "no token" is far less
    /// useful than "no token, and the file isn't even there".
    public func credentialProbeSummary() -> String {
        sources.map { $0.credentialProbeSummary() }.joined(separator: " ")
    }

    // MARK: - Write

    /// Persists to whichever store the read path resolved to.
    ///
    /// Deliberately re-runs the *same* resolution rather than caching it, so reads
    /// and writes can never disagree — a refresh persisted to a store we don't read
    /// from would be a silent no-op that repeats forever.
    @discardableResult
    public func writeOAuthSnapshot(_ snapshot: OAuthCredentialSnapshot) -> Bool {
        if let resolved = resolve() {
            // Never fan a failure out to the other store. Two stores holding
            // divergent credentials is worse than one honest failure, which
            // `OAuthRefreshService` already escalates into the recovery ladder.
            return sources[resolved.index].writeOAuthSnapshot(snapshot)
        }

        // Nothing resolved: fall back to the first store that at least exists.
        // Never create one — that is Claude Code's job, and inventing a credentials
        // file would just mask a genuine "reconnect required" state.
        guard let fallback = sources.first(where: { $0.storeExists }) else { return false }
        return fallback.writeOAuthSnapshot(snapshot)
    }

    // MARK: - Resolution

    private struct Resolution {
        let index: Int
        let snapshot: OAuthCredentialSnapshot
    }

    /// Precedence:
    ///
    /// 1. The first source (in declared order) holding a *usable* credential wins,
    ///    and probing stops there.
    /// 2. If every credential is expired, pick the best repair candidate: one with a
    ///    refresh token beats one without, then the later expiry, then declared order.
    /// 3. Nothing anywhere → nil.
    ///
    /// Declared order puts the credentials file first because post-migration Claude
    /// Code only reads and writes the file; a surviving Keychain entry is a frozen
    /// artifact that will never rotate again, so writing there would drift out of
    /// sync. But order alone is wrong for the migrated-then-downgraded user whose
    /// Keychain is live and whose file is a stale leftover — hence usability, not
    /// order, decides first.
    ///
    /// Stopping at the first usable credential also keeps the hot path cheap:
    /// `ClaudeCLIRecoveryService` polls `readOAuthSnapshot()` every 0.5s for up to
    /// 20s, and each `KeychainService` read spawns `/usr/bin/security`. For migrated
    /// users that subprocess is never spawned at all.
    private func resolve() -> Resolution? {
        var expired: [Resolution] = []

        for (index, source) in sources.enumerated() {
            guard let snapshot = source.readOAuthSnapshot() else { continue }
            if isUsable(snapshot) {
                return Resolution(index: index, snapshot: snapshot)
            }
            expired.append(Resolution(index: index, snapshot: snapshot))
        }

        return expired.min(by: Self.isBetterRepairCandidate)
    }

    /// A credential with no known expiry is treated as usable — that shape is a bare
    /// token from a hand-created Keychain entry, and the only way to learn whether it
    /// works is to use it.
    private func isUsable(_ snapshot: OAuthCredentialSnapshot) -> Bool {
        guard let expiry = snapshot.expiresAtDate else { return true }
        return expiry.timeIntervalSince(now()) > expirySkew
    }

    private static func isBetterRepairCandidate(_ lhs: Resolution, _ rhs: Resolution) -> Bool {
        let lhsRefreshable = lhs.snapshot.refreshToken?.isEmpty == false
        let rhsRefreshable = rhs.snapshot.refreshToken?.isEmpty == false
        if lhsRefreshable != rhsRefreshable { return lhsRefreshable }

        let lhsExpiry = lhs.snapshot.expiresAt ?? Int64.min
        let rhsExpiry = rhs.snapshot.expiresAt ?? Int64.min
        if lhsExpiry != rhsExpiry { return lhsExpiry > rhsExpiry }

        return lhs.index < rhs.index
    }
}
