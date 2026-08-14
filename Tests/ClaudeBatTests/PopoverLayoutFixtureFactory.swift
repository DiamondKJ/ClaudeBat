import Foundation
@testable import ClaudeBatCore

enum LayoutFixtureOperation: String, CaseIterable {
    case tokenRead
    case tokenSnapshotRead
    case tokenWrite
    case tokenFingerprint
    case credentialSource
    case storeExists
    case apiFetch
    case budgetReserve
    case budgetMutation
    case budgetRead
    case cacheRead
    case cacheWrite
    case recoveryRead
    case recoveryWrite
    case monitorRecord
    case monitorRead
    case authRefresh
    case cliRecovery
    case reachabilityRead
}

final class LayoutFixtureProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [LayoutFixtureOperation: Int] = [:]

    func record(_ operation: LayoutFixtureOperation) {
        lock.lock()
        counts[operation, default: 0] += 1
        lock.unlock()
    }

    func count(_ operation: LayoutFixtureOperation) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[operation, default: 0]
    }

    func nonzeroCounts() -> [LayoutFixtureOperation: Int] {
        lock.lock()
        defer { lock.unlock() }
        return counts.filter { $0.value != 0 }
    }
}

private final class LayoutTokenProvider: TokenProvider, @unchecked Sendable {
    let probe: LayoutFixtureProbe
    let snapshot: OAuthCredentialSnapshot?

    init(probe: LayoutFixtureProbe, snapshot: OAuthCredentialSnapshot?) {
        self.probe = probe
        self.snapshot = snapshot
    }

    func readToken() -> String? {
        probe.record(.tokenRead)
        return snapshot?.accessToken
    }

    func readOAuthSnapshot() -> OAuthCredentialSnapshot? {
        probe.record(.tokenSnapshotRead)
        return snapshot
    }

    func writeOAuthSnapshot(_ snapshot: OAuthCredentialSnapshot) -> Bool {
        probe.record(.tokenWrite)
        return false
    }

    func tokenFingerprint() -> String? {
        probe.record(.tokenFingerprint)
        return snapshot?.fingerprint
    }

    func credentialSource() -> CredentialSource? {
        probe.record(.credentialSource)
        return snapshot == nil ? nil : .credentialsFile
    }

    var storeExists: Bool {
        probe.record(.storeExists)
        return snapshot != nil
    }
}

private final class FailFastLayoutAPI: UsageFetching, @unchecked Sendable {
    let probe: LayoutFixtureProbe

    init(probe: LayoutFixtureProbe) {
        self.probe = probe
    }

    func fetchUsage(token: String) async throws -> UsageResponse {
        probe.record(.apiFetch)
        throw LayoutFixtureViolation.unexpectedExternalPath("usage API")
    }
}

private actor FailFastLayoutBudget: BudgetTracking {
    let probe: LayoutFixtureProbe

    init(probe: LayoutFixtureProbe) {
        self.probe = probe
    }

    func reserveRequest(allowWindowBypass: Bool) -> BudgetReservationDecision {
        probe.record(.budgetReserve)
        return .blockedByLocalWindow
    }

    func setRetryAfter(seconds: TimeInterval) {
        probe.record(.budgetMutation)
    }

    func isServerCooldownActive() -> Bool {
        probe.record(.budgetRead)
        return false
    }

    func clearServerCooldown() {
        probe.record(.budgetMutation)
    }

    func nextAllowedAt() -> Date? {
        probe.record(.budgetRead)
        return nil
    }

    func remainingBudget() -> Int {
        probe.record(.budgetRead)
        return 0
    }
}

private final class LayoutMemoryCache: UsageCaching, @unchecked Sendable {
    let probe: LayoutFixtureProbe
    let stored: Timestamped<UsageResponse>?

    init(probe: LayoutFixtureProbe, stored: Timestamped<UsageResponse>?) {
        self.probe = probe
        self.stored = stored
    }

    func read() -> Timestamped<UsageResponse>? {
        probe.record(.cacheRead)
        return stored
    }

    func write(_ response: UsageResponse) {
        probe.record(.cacheWrite)
    }
}

private final class LayoutMemoryRecoveryStore: RecoveryStatePersisting, @unchecked Sendable {
    let probe: LayoutFixtureProbe
    let snapshot: RecoverySnapshot?

    init(probe: LayoutFixtureProbe, snapshot: RecoverySnapshot?) {
        self.probe = probe
        self.snapshot = snapshot
    }

    func read() -> RecoverySnapshot? {
        probe.record(.recoveryRead)
        return snapshot
    }

    func write(_ snapshot: RecoverySnapshot) {
        probe.record(.recoveryWrite)
    }
}

private actor LayoutMemoryMonitor: AppMonitoring {
    let probe: LayoutFixtureProbe

    init(probe: LayoutFixtureProbe) {
        self.probe = probe
    }

    func record(event: MonitorEvent, status: MonitorStatus) {
        probe.record(.monitorRecord)
    }

    func latestStatus() -> MonitorStatus? {
        probe.record(.monitorRead)
        return nil
    }
}

private final class FailFastLayoutAuthRefresher: AuthRefreshing, @unchecked Sendable {
    let probe: LayoutFixtureProbe

    init(probe: LayoutFixtureProbe) {
        self.probe = probe
    }

    func refreshCredentials(currentSnapshot: OAuthCredentialSnapshot) async -> OAuthRefreshResult {
        probe.record(.authRefresh)
        return .unexpectedFailure("layout fixture must not refresh auth")
    }
}

private final class FailFastLayoutCLIRecoverer: ClaudeCLIRecovering, @unchecked Sendable {
    let probe: LayoutFixtureProbe

    init(probe: LayoutFixtureProbe) {
        self.probe = probe
    }

    func recoverAuth(
        baselineFingerprint: String?,
        baselineExpiresAt: Int64?,
        tokenProvider: any TokenProvider,
        timeout: TimeInterval
    ) async -> ClaudeCLIRecoveryResult {
        probe.record(.cliRecovery)
        return .launchFailed("layout fixture must not invoke Claude CLI")
    }
}

private final class LayoutReachability: NetworkReachabilityChecking, @unchecked Sendable {
    let probe: LayoutFixtureProbe

    init(probe: LayoutFixtureProbe) {
        self.probe = probe
    }

    func currentStatus() -> NetworkReachabilityStatus {
        probe.record(.reachabilityRead)
        return .reachable
    }
}

enum LayoutFixtureViolation: Error {
    case unexpectedExternalPath(String)
}

struct PopoverLayoutFixture {
    static let referenceDate = Date(timeIntervalSince1970: 1_786_708_800) // 2026-08-14T12:00:00Z
    static let fetchedAt = referenceDate.addingTimeInterval(-22)
    static let utc = TimeZone(secondsFromGMT: 0)!

    static let displayEnvironment = PopoverDisplayEnvironment(
        fixedNow: referenceDate,
        timeZone: utc,
        claudeInstalled: true
    )

    static func compactUsage() -> UsageResponse {
        response(modelLimits: [], extraUsage: ExtraUsage(isEnabled: false))
    }

    static func expandedUsage() -> UsageResponse {
        response(
            modelLimits: [
                ("model-fable", "Fable", 33),
                ("model-sonnet", "Sonnet", 61),
            ],
            extraUsage: ExtraUsage(
                isEnabled: true,
                monthlyLimit: 10_000,
                usedCredits: 1_234,
                utilization: 12.34
            )
        )
    }

    static func heavyUsage() -> UsageResponse {
        response(
            modelLimits: [
                ("model-a", "Fable", 11),
                ("model-b", "Sonnet", 22),
                ("model-c", "WWWWWWWWWWWWWWWWWWWWWWWW", 33),
                ("model-d", "Sonnet e\u{301} — 測試", 44),
            ],
            extraUsage: ExtraUsage(
                isEnabled: true,
                monthlyLimit: 999_999,
                usedCredits: 999_999,
                utilization: 100
            )
        )
    }

    static func depletedUsage(extraUsage: ExtraUsage? = ExtraUsage(isEnabled: false)) -> UsageResponse {
        response(
            fiveHourUtilization: 100,
            sevenDayUtilization: 50,
            modelLimits: [],
            extraUsage: extraUsage
        )
    }

    static func expiredUsage() -> UsageResponse {
        response(
            modelLimits: [],
            extraUsage: ExtraUsage(isEnabled: false),
            sessionReset: "2026-08-13T15:59:00.000Z",
            weeklyReset: "2026-08-21T18:00:00.000Z"
        )
    }

    static func response(
        fiveHourUtilization: Double = 8,
        sevenDayUtilization: Double = 50,
        modelLimits: [(id: String, label: String, percent: Double)],
        extraUsage: ExtraUsage?,
        sessionReset: String = "2026-08-14T15:59:00.000Z",
        weeklyReset: String = "2026-08-21T18:00:00.000Z"
    ) -> UsageResponse {
        let limits = modelLimits.map { item in
            UsageLimit(
                kind: "weekly_scoped",
                group: "weekly",
                percent: item.percent,
                severity: "normal",
                resetsAt: weeklyReset,
                isActive: false,
                scope: UsageLimitScope(
                    model: UsageLimitScopeModel(id: item.id, displayName: item.label)
                )
            )
        }

        return UsageResponse(
            fiveHour: UsagePeriod(utilization: fiveHourUtilization, resetsAt: sessionReset),
            sevenDay: UsagePeriod(utilization: sevenDayUtilization, resetsAt: weeklyReset),
            extraUsage: extraUsage,
            limits: limits
        )
    }

    @MainActor
    static func makeLayoutViewModel(
        usage: UsageResponse? = compactUsage(),
        tokenPresent: Bool = true,
        freshness: UsageViewModel.Freshness = .fresh,
        cachedDataReason: CachedDataReason? = nil,
        recoverySnapshot: RecoverySnapshot? = nil,
        errorMessage: String? = nil
    ) -> (viewModel: UsageViewModel, probe: LayoutFixtureProbe) {
        let probe = LayoutFixtureProbe()
        let snapshot = tokenPresent
            ? OAuthCredentialSnapshot(accessToken: "synthetic-layout-token-do-not-use")
            : nil
        let cached = usage.map { Timestamped(value: $0, fetchedAt: fetchedAt) }

        let viewModel = UsageViewModel(
            tokenProvider: LayoutTokenProvider(probe: probe, snapshot: snapshot),
            api: FailFastLayoutAPI(probe: probe),
            budget: FailFastLayoutBudget(probe: probe),
            cache: LayoutMemoryCache(probe: probe, stored: cached),
            recoveryStore: LayoutMemoryRecoveryStore(probe: probe, snapshot: recoverySnapshot),
            monitor: LayoutMemoryMonitor(probe: probe),
            authRefresher: FailFastLayoutAuthRefresher(probe: probe),
            claudeCLIRecoverer: FailFastLayoutCLIRecoverer(probe: probe),
            reachability: LayoutReachability(probe: probe),
            buildInfo: AppBuildInfo(
                appVersion: "fixture",
                buildFlavor: "test",
                gitCommit: "fixture",
                bundleIdentifier: "test.claudebat.layout"
            ),
            wakeCoalescingWindow: 5,
            wakeAuthRetryInterval: 30,
            startImmediately: false
        )

        viewModel.freshness = freshness
        viewModel.fetchedAt = usage == nil ? nil : fetchedAt
        viewModel.cachedDataReason = cachedDataReason
        viewModel.errorMessage = errorMessage
        return (viewModel, probe)
    }
}
