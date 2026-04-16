import Foundation

public enum BudgetReservationDecision: Equatable, Sendable {
    case granted
    case blockedByLocalWindow
    case blockedByServerCooldown
}

public enum NetworkReachabilityStatus: Equatable, Sendable {
    case unknown
    case reachable
    case unreachable
}

public protocol TokenProvider {
    func readToken() -> String?
    func readOAuthSnapshot() -> OAuthCredentialSnapshot?
    @discardableResult
    func writeOAuthSnapshot(_ snapshot: OAuthCredentialSnapshot) -> Bool
    func tokenFingerprint() -> String?
}

public protocol UsageFetching {
    func fetchUsage(token: String) async throws -> UsageResponse
}

public protocol BudgetTracking: Actor {
    func reserveRequest(allowWindowBypass: Bool) -> BudgetReservationDecision
    func setRetryAfter(seconds: TimeInterval)
    func isServerCooldownActive() -> Bool
    func clearServerCooldown()
    func nextAllowedAt() -> Date?
    func remainingBudget() -> Int
}

public protocol UsageCaching {
    func read() -> Timestamped<UsageResponse>?
    func write(_ response: UsageResponse)
}

public protocol RecoveryStatePersisting {
    func read() -> RecoverySnapshot?
    func write(_ snapshot: RecoverySnapshot)
}

public protocol AppMonitoring: Actor {
    func record(event: MonitorEvent, status: MonitorStatus)
    func latestStatus() -> MonitorStatus?
}

public protocol AuthRefreshing {
    func refreshCredentials(currentSnapshot: OAuthCredentialSnapshot) async -> OAuthRefreshResult
}

public protocol ClaudeCLIRecovering {
    func recoverAuth(
        baselineFingerprint: String?,
        baselineExpiresAt: Int64?,
        tokenProvider: any TokenProvider,
        timeout: TimeInterval
    ) async -> ClaudeCLIRecoveryResult
}

public protocol NetworkReachabilityChecking {
    func currentStatus() -> NetworkReachabilityStatus
}

public extension TokenProvider {
    func readOAuthSnapshot() -> OAuthCredentialSnapshot? {
        guard let token = readToken() else { return nil }
        return OAuthCredentialSnapshot(accessToken: token)
    }

    @discardableResult
    func writeOAuthSnapshot(_ snapshot: OAuthCredentialSnapshot) -> Bool {
        false
    }

    func tokenFingerprint() -> String? {
        readOAuthSnapshot()?.fingerprint
    }
}
