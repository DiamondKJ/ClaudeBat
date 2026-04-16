import Foundation
@testable import ClaudeBatCore

actor MockBudget: BudgetTracking {
    private var _allowRequests: Bool
    private var _serverCooldownActive: Bool
    private var _requestCount: Int = 0
    private var _nextAllowed: Date?
    private var _retryAfterCalled = false

    init(allowRequests: Bool = true, serverCooldownActive: Bool = false, nextAllowed: Date? = nil) {
        _allowRequests = allowRequests
        _serverCooldownActive = serverCooldownActive
        _nextAllowed = nextAllowed
    }

    func reserveRequest(allowWindowBypass: Bool) -> BudgetReservationDecision {
        if _serverCooldownActive {
            return .blockedByServerCooldown
        }
        if !_allowRequests && !allowWindowBypass {
            return .blockedByLocalWindow
        }
        _requestCount += 1
        return .granted
    }
    func setRetryAfter(seconds: TimeInterval) {
        _serverCooldownActive = true
        _retryAfterCalled = true
        _nextAllowed = Date().addingTimeInterval(seconds)
    }
    func isServerCooldownActive() -> Bool { _serverCooldownActive }
    func clearServerCooldown() { _serverCooldownActive = false }
    func nextAllowedAt() -> Date? { _nextAllowed }
    func remainingBudget() -> Int { _allowRequests ? 5 : 0 }

    // Actor-isolated accessors for test assertions
    func setAllowRequests(_ value: Bool) { _allowRequests = value }
    func setServerCooldownActive(_ value: Bool) { _serverCooldownActive = value }
    func setNextAllowed(_ value: Date?) { _nextAllowed = value }
    func getRequestCount() -> Int { _requestCount }
    func getRetryAfterCalled() -> Bool { _retryAfterCalled }
}

enum MockAPIResult {
    case success(UsageResponse)
    case failure(any Error)
}

final class MockAPI: UsageFetching, @unchecked Sendable {
    var response: UsageResponse?
    var error: (any Error)?
    var queuedResults: [MockAPIResult] = []
    private(set) var fetchCount = 0

    func fetchUsage(token: String) async throws -> UsageResponse {
        fetchCount += 1
        if !queuedResults.isEmpty {
            let next = queuedResults.removeFirst()
            switch next {
            case .success(let response):
                return response
            case .failure(let error):
                throw error
            }
        }
        if let error { throw error }
        return response!
    }
}

final class MockTokenProvider: TokenProvider, @unchecked Sendable {
    var snapshot: OAuthCredentialSnapshot?

    init(token: String? = nil, snapshot: OAuthCredentialSnapshot? = nil) {
        if let snapshot {
            self.snapshot = snapshot
        } else if let token {
            self.snapshot = OAuthCredentialSnapshot(accessToken: token)
        } else {
            self.snapshot = nil
        }
    }

    func readToken() -> String? { snapshot?.accessToken }
    func readOAuthSnapshot() -> OAuthCredentialSnapshot? { snapshot }
    @discardableResult
    func writeOAuthSnapshot(_ snapshot: OAuthCredentialSnapshot) -> Bool {
        self.snapshot = snapshot
        return true
    }
    func tokenFingerprint() -> String? { snapshot?.fingerprint }
}

final class MockCache: UsageCaching, @unchecked Sendable {
    var stored: Timestamped<UsageResponse>?

    func read() -> Timestamped<UsageResponse>? { stored }
    func write(_ response: UsageResponse) {
        stored = Timestamped(value: response, fetchedAt: Date())
    }
}

struct MockMonitorRecord: Sendable {
    let event: MonitorEvent
    let status: MonitorStatus
}

actor MockMonitor: AppMonitoring {
    private var records: [MockMonitorRecord] = []

    func record(event: MonitorEvent, status: MonitorStatus) {
        records.append(MockMonitorRecord(event: event, status: status))
    }

    func latestStatus() -> MonitorStatus? {
        records.last?.status
    }

    func allRecords() -> [MockMonitorRecord] {
        records
    }

    func latestRecord() -> MockMonitorRecord? {
        records.last
    }

    func containsEvent(
        category: MonitorEventCategory? = nil,
        action: String? = nil,
        trigger: FetchTrigger? = nil,
        outcome: FetchOutcome? = nil
    ) -> Bool {
        records.contains { record in
            if let category, record.event.category != category { return false }
            if let action, record.event.action != action { return false }
            if let trigger, record.event.trigger != trigger { return false }
            if let outcome, record.event.outcome != outcome { return false }
            return true
        }
    }

    func countEvents(
        category: MonitorEventCategory? = nil,
        action: String? = nil,
        trigger: FetchTrigger? = nil,
        outcome: FetchOutcome? = nil
    ) -> Int {
        records.filter { record in
            if let category, record.event.category != category { return false }
            if let action, record.event.action != action { return false }
            if let trigger, record.event.trigger != trigger { return false }
            if let outcome, record.event.outcome != outcome { return false }
            return true
        }.count
    }
}

final class MockRecoveryStore: RecoveryStatePersisting, @unchecked Sendable {
    var snapshot: RecoverySnapshot?

    func read() -> RecoverySnapshot? { snapshot }
    func write(_ snapshot: RecoverySnapshot) { self.snapshot = snapshot }
}

struct MockAuthRefresher: AuthRefreshing {
    var result: OAuthRefreshResult
    func refreshCredentials(currentSnapshot: OAuthCredentialSnapshot) async -> OAuthRefreshResult {
        result
    }
}

struct MockClaudeCLIRecoverer: ClaudeCLIRecovering {
    var result: ClaudeCLIRecoveryResult
    func recoverAuth(
        baselineFingerprint: String?,
        baselineExpiresAt: Int64?,
        tokenProvider: any TokenProvider,
        timeout: TimeInterval
    ) async -> ClaudeCLIRecoveryResult {
        result
    }
}

struct MockReachability: NetworkReachabilityChecking {
    var status: NetworkReachabilityStatus = .reachable
    func currentStatus() -> NetworkReachabilityStatus { status }
}
