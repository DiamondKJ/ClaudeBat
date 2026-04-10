import Foundation
import SwiftUI
import AppKit

@Observable
public final class UsageViewModel {
    // MARK: - Published State

    public var usage: UsageResponse?
    public var freshness: Freshness = .empty
    public var fetchedAt: Date?
    public var errorMessage: String?
    public var popoverIsOpen = false
    public var batExpression: BatExpression = .default
    public var cachedDataReason: CachedDataReason?
    public let buildInfo: AppBuildInfo

    public enum Freshness {
        case empty
        case fresh
        case stale
        case refreshing
    }

    public enum PopoverScreen: Equatable {
        case loading
        case reconnectClaude
        case offline
        case recovering
        case error
        case usage
    }

    public enum AuthPrompt: Equatable {
        case setup
        case reconnect
    }

    // MARK: - Private

    private let tokenProvider: any TokenProvider
    private let api: any UsageFetching
    private let budget: any BudgetTracking
    private var cache: any UsageCaching
    private let recoveryStore: any RecoveryStatePersisting
    private let monitor: any AppMonitoring
    private let authRefresher: any AuthRefreshing
    private let claudeCLIRecoverer: any ClaudeCLIRecovering
    private let reachability: any NetworkReachabilityChecking
    private let wakeCoalescingWindow: TimeInterval
    private let wakeAuthRetryInterval: TimeInterval

    private var pollingTimer: Timer?
    private var scheduledPollDelayOverride: TimeInterval?
    private var isFetching = false
    private var consecutiveFailures = 0
    private var selfHealAttempted = false
    private var sleepObserver: Any?
    private var screenWakeObserver: Any?
    private var machineWakeObserver: Any?
    private var displaySleeping = false
    private var trackedResetBoundary: Date?
    private var resetBoundaryPriorityAttempts = 0
    private var launchedAt = Date()
    private var lastAttemptAt: Date?
    private var lastSuccessAt: Date?
    private var lastFailureAt: Date?
    private var lastFailureReason: String?
    private var lastHTTPStatus: Int?
    private var lastRetryAfterSeconds: Int?
    private var lastWakeAt: Date?
    private var lastWakeSource: WakeSource?
    private var lastWakeNotificationAt: Date?
    private var activeWakeRecoveryStartedAt: Date?
    private var wakeAuthRetryPending = false
    private var recoverySnapshot: RecoverySnapshot
    private var sessionClassifierDecision: SessionClassifierDecision = .fetchUsageNormally
    private var authRecoveryPhase: AuthRecoveryPhase = .idle
    private var authRecoveryResult: AuthRecoveryResult?
    private var isAuthRecoveryInFlight = false

    private static let basePollOpen: TimeInterval = 120
    private static let basePollClosed: TimeInterval = 120
    private static let maxBackoff: TimeInterval = 1800
    private static let maxResetBoundaryPriorityAttempts = 2
    private static let decodingRetryInterval: TimeInterval = 60
    private static let retryAfterBufferSeconds = 5
    private static let wakeAuthRetryGraceWindow: TimeInterval = 120
    private static let hiddenClaudeCooldown: TimeInterval = 20 * 60
    private static let hiddenClaudeTimeout: TimeInterval = 20

    private var pollInterval: TimeInterval {
        let base = popoverIsOpen ? Self.basePollOpen : Self.basePollClosed
        if consecutiveFailures == 0 { return base }
        let backoff = base * pow(2.0, Double(consecutiveFailures - 1))
        return min(backoff, Self.maxBackoff)
    }

    private var activePollInterval: TimeInterval {
        scheduledPollDelayOverride ?? pollInterval
    }

    private var cacheAgeSeconds: Int? {
        fetchedAt.map { max(0, Int(Date().timeIntervalSince($0))) }
    }

    private var isUsingCachedData: Bool {
        guard usage != nil else { return false }
        if cachedDataReason != nil { return true }
        return freshness != .fresh
    }

    private var hasRefreshableCredentials: Bool {
        guard let snapshot = tokenProvider.readOAuthSnapshot() else { return false }
        guard let refreshToken = snapshot.refreshToken else { return false }
        return !refreshToken.isEmpty
    }

    private var cachedSessionHasEnded: Bool {
        guard let resetAt = usage?.fiveHour.resetsAtDate else { return false }
        return Date() > resetAt
    }

    private var cachedUsageBelongsToCurrentSession: Bool {
        guard let resetAt = usage?.fiveHour.resetsAtDate else { return usage != nil }
        if Date() <= resetAt {
            return true
        }
        guard let lastSuccessAt else { return false }
        return lastSuccessAt >= resetAt
    }

    private var needsSessionAwareRecovery: Bool {
        usage != nil && !cachedUsageBelongsToCurrentSession
    }

    private var shouldPreemptivelyRefreshAuth: Bool {
        needsSessionAwareRecovery && hasRefreshableCredentials
    }

    private var isRecoveringAuth: Bool {
        isAuthRecoveryInFlight || authRecoveryPhase == .awaitingUsageValidation
    }

    // MARK: - Init

    public init(
        tokenProvider: any TokenProvider = KeychainService(),
        api: any UsageFetching = UsageAPIService(),
        budget: any BudgetTracking = SlidingWindowBudget(),
        cache: any UsageCaching = UsageCache(),
        recoveryStore: any RecoveryStatePersisting = RecoveryStateStore(),
        monitor: (any AppMonitoring)? = nil,
        authRefresher: (any AuthRefreshing)? = nil,
        claudeCLIRecoverer: any ClaudeCLIRecovering = ClaudeCLIRecoveryService(),
        reachability: any NetworkReachabilityChecking = NetworkReachabilityService(),
        buildInfo: AppBuildInfo = .current,
        wakeCoalescingWindow: TimeInterval = 5,
        wakeAuthRetryInterval: TimeInterval = 30,
        startImmediately: Bool = true
    ) {
        self.tokenProvider = tokenProvider
        self.api = api
        self.budget = budget
        self.cache = cache
        self.recoveryStore = recoveryStore
        self.buildInfo = buildInfo
        self.monitor = monitor ?? MonitorService(buildInfo: buildInfo)
        self.authRefresher = authRefresher ?? OAuthRefreshService(tokenProvider: tokenProvider)
        self.claudeCLIRecoverer = claudeCLIRecoverer
        self.reachability = reachability
        self.wakeCoalescingWindow = wakeCoalescingWindow
        self.wakeAuthRetryInterval = wakeAuthRetryInterval
        self.recoverySnapshot = recoveryStore.read() ?? RecoverySnapshot()
        self.authRecoveryPhase = self.recoverySnapshot.authRecoveryPhase ?? .idle
        self.authRecoveryResult = self.recoverySnapshot.lastRecoveryResult

        if let cached = cache.read() {
            usage = cached.value
            fetchedAt = cached.fetchedAt
            lastSuccessAt = recoverySnapshot.lastSuccessfulUsageAt ?? cached.fetchedAt
            freshness = cached.age > 60 ? .stale : .fresh
        } else {
            lastSuccessAt = recoverySnapshot.lastSuccessfulUsageAt
        }

        if startImmediately {
            observeSleepWake()
            startPolling()

            Task { @MainActor in
                await fetchIfBudgetAllows(trigger: .appLaunch)
            }
        }
    }

    deinit {
        pollingTimer?.invalidate()
        if let obs = sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(obs) }
        if let obs = screenWakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(obs) }
        if let obs = machineWakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(obs) }
    }

    // MARK: - Public Actions

    public func recordAppLaunch() {
        launchedAt = Date()
        recordMonitorEvent(
            MonitorEvent(
                category: .lifecycle,
                action: "launch",
                trigger: .appLaunch,
                message: buildInfo.isLocalMonitorBuild ? "local monitor build active" : "app launched"
            )
        )
    }

    public func recordAppTermination() {
        let event = MonitorEvent(category: .lifecycle, action: "terminate", message: "app shutting down")
        let status = makeMonitorStatus(appRunning: false)
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await monitor.record(event: event, status: status)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 1)
    }

    public func onPopoverOpen() {
        popoverIsOpen = true
        restartPolling(reason: "popover_open")
        recordMonitorEvent(MonitorEvent(category: .lifecycle, action: "popover_open"))

        let needsFetch: Bool
        if hasResetBoundaryPassed {
            needsFetch = true
        } else if let age = fetchedAt.map({ Date().timeIntervalSince($0) }), age > 60 {
            needsFetch = true
        } else {
            needsFetch = false
        }

        if needsFetch {
            Task { @MainActor in
                await fetchIfBudgetAllows(trigger: .popoverOpen)
            }
        }
    }

    public func onPopoverClose() {
        popoverIsOpen = false
        restartPolling(reason: "popover_close")
        recordMonitorEvent(MonitorEvent(category: .lifecycle, action: "popover_close"))
    }

    // MARK: - Session-Aware Recovery

    @MainActor
    private func handleSessionPreflightIfNeeded(for trigger: FetchTrigger) async -> Bool {
        guard shouldRunSessionClassifier(for: trigger) else { return false }

        let decision = classifySession(for: trigger)
        sessionClassifierDecision = decision
        recordMonitorEvent(
            MonitorEvent(
                category: .auth,
                action: "session_classifier_decision",
                trigger: trigger,
                message: decision.rawValue
            )
        )

        switch decision {
        case .fetchUsageNormally:
            return false
        case .showRecoveringAndRetryLater:
            return true
        case .showOffline:
            if usage == nil {
                errorMessage = "ClaudeBat could not reach the internet to refresh your usage."
            } else {
                freshness = .stale
                setCachedDataReason(.networkError)
            }
            return true
        case .showReconnect:
            if usage == nil {
                freshness = .empty
            } else {
                freshness = .stale
                setCachedDataReason(hasNoAuth ? .noToken : .authInvalid)
            }
            authRecoveryPhase = .failedRequiresReconnect
            authRecoveryResult = .missingCredentials
            persistRecoverySnapshot {
                $0.authRecoveryPhase = self.authRecoveryPhase
                $0.lastRecoveryAttemptAt = Date()
                $0.lastRecoveryResult = .missingCredentials
            }
            recordMonitorEvent(
                MonitorEvent(
                    category: .auth,
                    action: "manual_reconnect_required",
                    trigger: trigger,
                    message: "automatic recovery unavailable"
                )
            )
            return true
        case .refreshAuthThenFetch:
            await startAuthRecovery(reason: trigger.rawValue, trigger: trigger)
            return true
        }
    }

    private func shouldRunSessionClassifier(for trigger: FetchTrigger) -> Bool {
        if isAuthRecoveryInFlight { return true }

        switch trigger {
        case .appLaunch, .screenWake, .machineWake:
            return true
        case .popoverOpen:
            return fetchedAt == nil || sessionDataNeedsRefresh || isUsingCachedData
        case .pollTimer:
            return sessionDataNeedsRefresh || lastFailureReason == FetchOutcome.http401.rawValue
        case .resetBoundary, .selfHeal:
            return false
        }
    }

    private func classifySession(for trigger: FetchTrigger) -> SessionClassifierDecision {
        if isAuthRecoveryInFlight {
            return .showRecoveringAndRetryLater
        }

        if !reachability.isReachable() {
            return .showOffline
        }

        if shouldPreemptivelyRefreshAuth {
            recordMonitorEvent(
                MonitorEvent(
                    category: .auth,
                    action: "previous_session_detected",
                    trigger: trigger,
                    message: "cached usage belongs to a previous session"
                )
            )
            return .refreshAuthThenFetch
        }

        if sessionDataNeedsRefresh {
            return hasRefreshableCredentials ? .refreshAuthThenFetch : .showReconnect
        }

        if lastFailureReason == FetchOutcome.http401.rawValue || cachedDataReason == .authInvalid {
            return hasRefreshableCredentials ? .refreshAuthThenFetch : .showReconnect
        }

        return .fetchUsageNormally
    }

    @MainActor
    private func startAuthRecovery(reason: String, trigger: FetchTrigger) async {
        guard !isAuthRecoveryInFlight else { return }
        guard reachability.isReachable() else {
            authRecoveryResult = .offline
            authRecoveryPhase = .failedRequiresReconnect
            return
        }
        guard let currentSnapshot = tokenProvider.readOAuthSnapshot() else {
            authRecoveryPhase = .failedRequiresReconnect
            authRecoveryResult = .missingCredentials
            if usage == nil {
                freshness = .empty
            } else {
                freshness = .stale
                setCachedDataReason(.noToken)
            }
            persistRecoverySnapshot {
                $0.authRecoveryPhase = self.authRecoveryPhase
                $0.lastRecoveryAttemptAt = Date()
                $0.lastRecoveryResult = self.authRecoveryResult
            }
            recordMonitorEvent(
                MonitorEvent(category: .auth, action: "manual_reconnect_required", trigger: trigger, message: "missing OAuth credentials")
            )
            return
        }

        isAuthRecoveryInFlight = true
        authRecoveryPhase = .nativeRefreshInFlight
        authRecoveryResult = nil
        wakeAuthRetryPending = false
        pollingTimer?.invalidate()
        freshness = usage == nil ? .empty : .refreshing
        persistRecoverySnapshot {
            $0.authRecoveryPhase = .nativeRefreshInFlight
            $0.lastRecoveryAttemptAt = Date()
            $0.lastRecoveryResult = nil
        }
        recordMonitorEvent(
            MonitorEvent(category: .auth, action: "auth_recovery_started", trigger: trigger, message: reason)
        )
        recordMonitorEvent(
            MonitorEvent(category: .auth, action: "native_refresh_started", trigger: trigger, message: "attempting refresh token exchange")
        )

        let result = await authRefresher.refreshCredentials(currentSnapshot: currentSnapshot)
        switch result {
        case .success(let newFingerprint):
            authRecoveryPhase = .awaitingUsageValidation
            authRecoveryResult = nil
            persistRecoverySnapshot {
                let now = Date()
                $0.authRecoveryPhase = .awaitingUsageValidation
                $0.lastSuccessfulAuthRefreshAt = now
                $0.lastSuccessfulAuthRefreshMethod = .native
                if $0.lastTokenFingerprint != newFingerprint {
                    $0.lastTokenFingerprint = newFingerprint
                    $0.lastTokenFingerprintChangedAt = now
                }
            }
            recordMonitorEvent(
                MonitorEvent(category: .auth, action: "native_refresh_succeeded", trigger: trigger, message: "refresh token exchange completed")
            )
            let validationStartedAt = Date()
            await fetchIfBudgetAllows(trigger: trigger, allowSessionPreflight: false)
            if usageValidationSucceeded(since: validationStartedAt) {
                finishSuccessfulRecovery(trigger: trigger)
            } else if lastFailureReason == FetchOutcome.rateLimited.rawValue || lastFailureReason == FetchOutcome.serverCooldownBlocked.rawValue {
                isAuthRecoveryInFlight = false
                authRecoveryPhase = .awaitingUsageValidation
                recordMonitorEvent(
                    MonitorEvent(
                        category: .auth,
                        action: "usage_validation_after_refresh_failed",
                        trigger: trigger,
                        outcome: .rateLimited,
                        message: "usage validation is waiting on retry-after"
                    )
                )
            } else if lastFailureReason == FetchOutcome.networkError.rawValue {
                isAuthRecoveryInFlight = false
                authRecoveryPhase = .failedRequiresReconnect
                authRecoveryResult = .offline
                persistRecoverySnapshot {
                    $0.authRecoveryPhase = .failedRequiresReconnect
                    $0.lastRecoveryAttemptAt = Date()
                    $0.lastRecoveryResult = .offline
                }
            } else if lastFailureReason == FetchOutcome.decodingError.rawValue {
                isAuthRecoveryInFlight = false
                authRecoveryPhase = .awaitingUsageValidation
                recordMonitorEvent(
                    MonitorEvent(
                        category: .auth,
                        action: "usage_validation_after_refresh_failed",
                        trigger: trigger,
                        outcome: .decodingError,
                        message: "usage validation returned an undecodable response"
                    )
                )
            } else {
                await attemptClaudeCLIFallback(trigger: trigger)
            }
        case .missingRefreshToken:
            failRecovery(.missingCredentials, trigger: trigger, reason: "missing refresh token")
        case .networkFailure(let message):
            authRecoveryResult = .offline
            authRecoveryPhase = .failedRequiresReconnect
            if usage == nil {
                errorMessage = "ClaudeBat could not reach the internet to restore Claude Code."
            } else {
                freshness = .stale
                setCachedDataReason(.networkError)
            }
            persistRecoverySnapshot {
                $0.authRecoveryPhase = self.authRecoveryPhase
                $0.lastRecoveryAttemptAt = Date()
                $0.lastRecoveryResult = .offline
            }
            recordMonitorEvent(
                MonitorEvent(category: .auth, action: "native_refresh_failed", trigger: trigger, message: message)
            )
            isAuthRecoveryInFlight = false
        case .authRejected(let code):
            recordMonitorEvent(
                MonitorEvent(category: .auth, action: "native_refresh_failed", trigger: trigger, outcome: .http401, message: "refresh rejected (\(code.map(String.init) ?? "unknown"))")
            )
            await attemptClaudeCLIFallback(trigger: trigger)
        case .unexpectedFailure(let message):
            recordMonitorEvent(
                MonitorEvent(category: .auth, action: "native_refresh_failed", trigger: trigger, message: message)
            )
            await attemptClaudeCLIFallback(trigger: trigger)
        }
    }

    @MainActor
    private func attemptClaudeCLIFallback(trigger: FetchTrigger) async {
        let now = Date()
        if let last = recoverySnapshot.lastHiddenClaudeActivationAt,
           now.timeIntervalSince(last) < Self.hiddenClaudeCooldown {
            failRecovery(.timedOut, trigger: trigger, reason: "hidden Claude activation is cooling down")
            return
        }

        authRecoveryPhase = .claudeCLIRecoveryInFlight
        persistRecoverySnapshot {
            $0.authRecoveryPhase = .claudeCLIRecoveryInFlight
            $0.lastHiddenClaudeActivationAt = now
        }
        recordMonitorEvent(
            MonitorEvent(category: .auth, action: "claude_cli_recovery_started", trigger: trigger, message: "launching hidden Claude session")
        )

        let baseline = tokenProvider.readOAuthSnapshot()
        let result = await claudeCLIRecoverer.recoverAuth(
            baselineFingerprint: baseline?.fingerprint,
            baselineExpiresAt: baseline?.expiresAt,
            tokenProvider: tokenProvider,
            timeout: Self.hiddenClaudeTimeout
        )

        switch result {
        case .success:
            persistRecoverySnapshot {
                let now = Date()
                $0.lastSuccessfulAuthRefreshAt = now
                $0.lastSuccessfulAuthRefreshMethod = .claudeCLI
                let newFingerprint = self.tokenProvider.tokenFingerprint()
                if $0.lastTokenFingerprint != newFingerprint {
                    $0.lastTokenFingerprint = newFingerprint
                    $0.lastTokenFingerprintChangedAt = now
                }
                $0.authRecoveryPhase = .awaitingUsageValidation
            }
            recordMonitorEvent(
                MonitorEvent(category: .auth, action: "claude_cli_recovery_succeeded", trigger: trigger, message: "hidden Claude session refreshed auth")
            )
            authRecoveryPhase = .awaitingUsageValidation
            let validationStartedAt = Date()
            await fetchIfBudgetAllows(trigger: trigger, allowSessionPreflight: false)
            if usageValidationSucceeded(since: validationStartedAt) {
                finishSuccessfulRecovery(trigger: trigger)
            } else if lastFailureReason == FetchOutcome.rateLimited.rawValue || lastFailureReason == FetchOutcome.serverCooldownBlocked.rawValue {
                isAuthRecoveryInFlight = false
                authRecoveryPhase = .awaitingUsageValidation
            } else if lastFailureReason == FetchOutcome.decodingError.rawValue {
                isAuthRecoveryInFlight = false
                authRecoveryPhase = .awaitingUsageValidation
                recordMonitorEvent(
                    MonitorEvent(
                        category: .auth,
                        action: "usage_validation_after_refresh_failed",
                        trigger: trigger,
                        outcome: .decodingError,
                        message: "usage validation returned an undecodable response"
                    )
                )
            } else {
                failRecovery(.authRejected, trigger: trigger, reason: "usage validation still failed after hidden Claude recovery")
            }
        case .timedOut:
            failRecovery(.timedOut, trigger: trigger, reason: "hidden Claude recovery timed out")
        case .launchFailed(let message):
            failRecovery(.unexpectedFailure, trigger: trigger, reason: message)
        }
    }

    private func usageValidationSucceeded(since startedAt: Date) -> Bool {
        guard let lastSuccessAt else { return false }
        return lastSuccessAt >= startedAt
    }

    @MainActor
    private func finishSuccessfulRecovery(trigger: FetchTrigger) {
        isAuthRecoveryInFlight = false
        authRecoveryPhase = .idle
        authRecoveryResult = .success
        clearWakeRecoveryState()
        persistRecoverySnapshot {
            $0.authRecoveryPhase = .idle
            $0.lastRecoveryAttemptAt = Date()
            $0.lastRecoveryResult = .success
        }
        recordMonitorEvent(
            MonitorEvent(category: .auth, action: "auth_recovery_succeeded", trigger: trigger, message: "usage validation succeeded")
        )
    }

    @MainActor
    private func failRecovery(_ result: AuthRecoveryResult, trigger: FetchTrigger, reason: String) {
        isAuthRecoveryInFlight = false
        authRecoveryPhase = .failedRequiresReconnect
        authRecoveryResult = result
        if usage == nil {
            freshness = .empty
            errorMessage = "ClaudeBat couldn't restore Claude Code automatically."
        } else {
            freshness = .stale
            setCachedDataReason(hasNoAuth ? .noToken : .authInvalid)
        }
        persistRecoverySnapshot {
            $0.authRecoveryPhase = .failedRequiresReconnect
            $0.lastRecoveryAttemptAt = Date()
            $0.lastRecoveryResult = result
        }
        recordMonitorEvent(
            MonitorEvent(category: .auth, action: "auth_recovery_failed", trigger: trigger, message: reason)
        )
        recordMonitorEvent(
            MonitorEvent(category: .auth, action: "manual_reconnect_required", trigger: trigger, message: reason)
        )
    }

    private func persistRecoverySnapshot(_ mutate: (inout RecoverySnapshot) -> Void) {
        var snapshot = recoverySnapshot
        mutate(&snapshot)
        recoverySnapshot = snapshot
        recoveryStore.write(snapshot)
    }

    // MARK: - Fetch Logic

    @MainActor
    func fetchIfBudgetAllows(trigger originalTrigger: FetchTrigger = .pollTimer) async {
        await fetchIfBudgetAllows(trigger: originalTrigger, allowSessionPreflight: true)
    }

    @MainActor
    private func fetchIfBudgetAllows(trigger originalTrigger: FetchTrigger = .pollTimer, allowSessionPreflight: Bool) async {
        if allowSessionPreflight {
            let handled = await handleSessionPreflightIfNeeded(for: originalTrigger)
            if handled {
                return
            }
        }

        if isFetching {
            recordMonitorEvent(
                MonitorEvent(
                    category: .fetch,
                    action: "skipped",
                    trigger: originalTrigger,
                    outcome: .skippedAlreadyFetching,
                    message: "fetch already in progress"
                )
            )
            return
        }

        var trigger = originalTrigger
        let dataAge = fetchedAt.map { Date().timeIntervalSince($0) } ?? .infinity
        if dataAge > 600 && !selfHealAttempted {
            selfHealAttempted = true
            await budget.clearServerCooldown()
            consecutiveFailures = 0
            trigger = .selfHeal
            restartPolling(reason: "self_heal")
        } else if dataAge > 600 && selfHealAttempted {
            errorMessage = "Unable to refresh — check your connection"
            freshness = .stale
        }

        trigger = prioritizedTrigger(for: trigger)

        isFetching = true
        defer { isFetching = false }

        lastAttemptAt = Date()
        recordMonitorEvent(
            MonitorEvent(category: .fetch, action: "started", trigger: trigger, message: "begin fetch attempt")
        )

        let canGo = await budget.canRequest()
        if !canGo {
            if trigger == .resetBoundary {
                let serverBlocked = await budget.isServerCooldownActive()
                if serverBlocked {
                    let nextDelay = await rescheduleForBudgetAvailability(reason: "server_cooldown_wait")
                    lastFailureAt = Date()
                    lastFailureReason = FetchOutcome.serverCooldownBlocked.rawValue
                    lastRetryAfterSeconds = nextDelay
                    recordMonitorEvent(
                        MonitorEvent(
                            category: .fetch,
                            action: "blocked",
                            trigger: .resetBoundary,
                            outcome: .serverCooldownBlocked,
                            message: "server retry-after still active",
                            retryAfterSeconds: nextDelay
                        )
                    )
                    return
                }
            } else {
                let serverBlocked = await budget.isServerCooldownActive()
                let nextDelay = await rescheduleForBudgetAvailability(
                    reason: serverBlocked ? "server_cooldown_wait" : "budget_window_wait"
                )
                lastFailureAt = Date()
                lastFailureReason = serverBlocked
                    ? FetchOutcome.serverCooldownBlocked.rawValue
                    : FetchOutcome.budgetBlocked.rawValue
                lastRetryAfterSeconds = serverBlocked ? nextDelay : nil
                recordMonitorEvent(
                    MonitorEvent(
                        category: .fetch,
                        action: "blocked",
                        trigger: trigger,
                        outcome: serverBlocked ? .serverCooldownBlocked : .budgetBlocked,
                        message: serverBlocked
                            ? "server retry-after still active"
                            : "local sliding-window budget exhausted",
                        retryAfterSeconds: serverBlocked ? nextDelay : nil
                    )
                )
                return
            }
        }

        guard let token = tokenProvider.readToken() else {
            lastFailureAt = Date()
            lastFailureReason = FetchOutcome.noToken.rawValue
            lastHTTPStatus = nil
            lastRetryAfterSeconds = nil
            if usage == nil {
                freshness = .empty
                errorMessage = nil
                setCachedDataReason(nil)
            } else {
                freshness = .stale
                setCachedDataReason(.noToken)
            }

            recordMonitorEvent(
                MonitorEvent(
                    category: .auth,
                    action: "missing_token",
                    trigger: trigger,
                    outcome: .noToken,
                    message: "keychain token unavailable"
                )
            )
            return
        }

        if usage != nil {
            freshness = .refreshing
            startBatWink()
        } else {
            freshness = .empty
        }

        await budget.recordRequest()
        recordResetBoundaryRequestIfNeeded(trigger)

        do {
            let response = try await api.fetchUsage(token: token)
            let successAt = Date()
            cache.write(response)
            usage = response
            fetchedAt = successAt
            lastSuccessAt = successAt
            lastHTTPStatus = 200
            lastRetryAfterSeconds = nil
            freshness = .fresh
            errorMessage = nil
            consecutiveFailures = 0
            selfHealAttempted = false
            clearWakeRecoveryState()
            restartPolling(reason: "fetch_success")
            stopBatWink()
            clearCachedDataState()
            persistRecoverySnapshot {
                $0.lastSuccessfulUsageAt = successAt
                $0.lastSuccessfulUsageSessionResetAt = response.fiveHour.resetsAtDate
                $0.authRecoveryPhase = self.authRecoveryPhase
                if let fingerprint = self.tokenProvider.tokenFingerprint(), $0.lastTokenFingerprint != fingerprint {
                    $0.lastTokenFingerprint = fingerprint
                    $0.lastTokenFingerprintChangedAt = successAt
                }
            }

            recordMonitorEvent(
                MonitorEvent(
                    category: .fetch,
                    action: "completed",
                    trigger: trigger,
                    outcome: .success,
                    message: "usage refreshed"
                )
            )
            if isAuthRecoveryInFlight || authRecoveryPhase == .awaitingUsageValidation {
                recordMonitorEvent(
                    MonitorEvent(
                        category: .auth,
                        action: "usage_validation_after_refresh_succeeded",
                        trigger: trigger,
                        outcome: .success,
                        message: "fresh usage validated after auth recovery"
                    )
                )
            }
        } catch let error as UsageAPIError {
            stopBatWink()
            await handleUsageAPIError(error, trigger: trigger)
        } catch {
            stopBatWink()
            handleUnknownError(error, trigger: trigger)
        }
    }

    // MARK: - Polling

    private func startPolling() {
        restartPolling(reason: "startup")
    }

    private func restartPolling(reason: String) {
        restartPolling(reason: reason, after: nil)
    }

    private func restartPolling(reason: String, after delay: TimeInterval?) {
        pollingTimer?.invalidate()
        let interval = max(1, delay ?? pollInterval)
        let repeats = delay == nil
        scheduledPollDelayOverride = repeats ? nil : interval

        let timer = Timer(timeInterval: interval, repeats: repeats) { [weak self] _ in
            guard let self else { return }
            if !repeats {
                self.scheduledPollDelayOverride = nil
            }
            Task { @MainActor in
                await self.fetchIfBudgetAllows(trigger: .pollTimer)
            }
        }
        pollingTimer = timer
        RunLoop.main.add(timer, forMode: .common)

        recordMonitorEvent(
            MonitorEvent(category: .timer, action: "restarted", message: reason)
        )
    }

    // MARK: - Sleep/Wake

    private func observeSleepWake() {
        let nc = NSWorkspace.shared.notificationCenter

        sleepObserver = nc.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSleep()
        }

        screenWakeObserver = nc.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWake(source: .screen)
        }

        machineWakeObserver = nc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWake(source: .machine)
        }
    }

    func handleWake(source: WakeSource) {
        let now = Date()
        displaySleeping = false
        lastWakeAt = now
        lastWakeSource = source

        recordMonitorEvent(
            MonitorEvent(
                category: .lifecycle,
                action: "wake_observed",
                wakeSource: source,
                message: "wake observed"
            )
        )

        if shouldCoalesceWake(at: now) {
            recordMonitorEvent(
                MonitorEvent(
                    category: .lifecycle,
                    action: "wake_coalesced",
                    wakeSource: source,
                    message: "duplicate wake notification ignored"
                )
            )
            return
        }

        lastWakeNotificationAt = now
        activeWakeRecoveryStartedAt = now
        wakeAuthRetryPending = false

        restartPolling(reason: "\(source.rawValue)_wake")
        let dataAge = fetchedAt.map { Date().timeIntervalSince($0) } ?? .infinity
        let trigger: FetchTrigger = source == .screen ? .screenWake : .machineWake
        if dataAge > 300 {
            Task { @MainActor in
                let serverBlocked = await self.budget.isServerCooldownActive()
                guard !serverBlocked else {
                    let nextDelay = await self.rescheduleForBudgetAvailability(reason: "wake_retry_after_wait")
                    self.lastFailureAt = Date()
                    self.lastFailureReason = FetchOutcome.serverCooldownBlocked.rawValue
                    self.lastRetryAfterSeconds = nextDelay
                    self.recordMonitorEvent(
                        MonitorEvent(
                            category: .fetch,
                            action: "blocked",
                            trigger: trigger,
                            outcome: .serverCooldownBlocked,
                            wakeSource: source,
                            message: "wake fetch blocked by retry-after",
                            retryAfterSeconds: nextDelay
                        )
                    )
                    return
                }
                await self.fetchIfBudgetAllows(trigger: trigger)
            }
        } else {
            Task { @MainActor in
                await self.fetchIfBudgetAllows(trigger: trigger)
            }
        }
    }

    private func handleSleep() {
        displaySleeping = true
        pollingTimer?.invalidate()
        clearWakeRecoveryState()
        recordMonitorEvent(
            MonitorEvent(category: .lifecycle, action: "sleep_observed", message: "display sleep observed")
        )
    }

    // MARK: - Bat Wink Animation

    private var winkTimer: Timer?

    private func startBatWink() {
        let expressions: [BatExpression] = [.winking, .default]
        var index = 0
        batExpression = .winking
        winkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            index = (index + 1) % expressions.count
            self?.batExpression = expressions[index]
        }
    }

    private func stopBatWink() {
        winkTimer?.invalidate()
        winkTimer = nil
        batExpression = .default
    }

    // MARK: - Computed

    public var sessionRemaining: Int {
        usage?.fiveHour.remainingInt ?? 0
    }

    public var isFullyMaxed: Bool {
        guard let u = usage else { return false }
        return u.fiveHour.remaining <= 0 && u.sevenDay.remaining <= 0
    }

    public var sessionDataNeedsRefresh: Bool {
        guard let usage, let resetAt = usage.fiveHour.resetsAtDate else { return false }
        guard Date() > resetAt else { return false }
        guard let lastSuccessAt else { return true }
        return lastSuccessAt < resetAt
    }

    public var popoverScreen: PopoverScreen {
        if isRecoveringAuth || wakeAuthRetryPending {
            return .recovering
        }

        if usage == nil {
            if hasNoAuth {
                return .reconnectClaude
            }
            if isOfflineErrorMessage(errorMessage) {
                return .offline
            }
            if hasError {
                return .error
            }
            return .loading
        }

        guard sessionDataNeedsRefresh else {
            return .usage
        }

        switch cachedDataReason {
        case .authInvalid, .noToken:
            return .reconnectClaude
        case .networkError:
            return .offline
        case .serverError, .rateLimited:
            return .recovering
        case nil:
            return freshness == .refreshing ? .loading : .recovering
        }
    }

    public var authPrompt: AuthPrompt {
        if cachedDataReason == .authInvalid || cachedDataReason == .noToken || lastFailureReason == FetchOutcome.http401.rawValue || lastSuccessAt != nil {
            return .reconnect
        }
        return .setup
    }

    public var offlineErrorMessage: String {
        if sessionDataNeedsRefresh {
            return "ClaudeBat could not refresh your usage after the reset because your Mac is offline."
        }
        return errorMessage ?? "ClaudeBat could not reach the usage endpoint. Check your internet connection."
    }

    public var recoveryMessage: String {
        if authRecoveryPhase == .nativeRefreshInFlight {
            return "Restoring Claude Code connection."
        }

        if authRecoveryPhase == .claudeCLIRecoveryInFlight {
            return "Refreshing Claude Code in the background."
        }

        if wakeAuthRetryPending {
            return "ClaudeBat is retrying Claude Code auth after wake."
        }

        switch cachedDataReason {
        case .rateLimited:
            return "ClaudeBat is waiting for the usage endpoint to allow another refresh after the reset."
        case .serverError:
            return "ClaudeBat is waiting for a clean usage response after the reset."
        case .authInvalid, .noToken, .networkError, nil:
            return "ClaudeBat is refreshing your usage after the reset."
        }
    }

    public var shouldShowCachedBanner: Bool {
        popoverScreen == .usage && cachedDataReason != nil
    }

    public var shouldShowMenuBarUsage: Bool {
        usage != nil && !sessionDataNeedsRefresh && !wakeAuthRetryPending && !isRecoveringAuth
    }

    public var hasNoAuth: Bool {
        tokenProvider.readOAuthSnapshot() == nil && tokenProvider.readToken() == nil
    }

    public var hasError: Bool {
        usage == nil && errorMessage != nil
    }

    private var hasResetBoundaryPassed: Bool {
        guard let resetsAt = usage?.fiveHour.resetsAtDate else { return false }
        return Date() > resetsAt
    }

    // MARK: - Failure Handling

    private func handleUsageAPIError(_ error: UsageAPIError, trigger: FetchTrigger) async {
        switch error {
        case .rateLimited(let retryAfter):
            let delay = sanitizedRetryAfter(retryAfter)
            lastFailureAt = Date()
            lastFailureReason = FetchOutcome.rateLimited.rawValue
            lastHTTPStatus = 429
            lastRetryAfterSeconds = delay

            await budget.setRetryAfter(seconds: TimeInterval(delay))
            let nextDelay = await rescheduleForBudgetAvailability(reason: "rate_limited_retry_after")
            lastRetryAfterSeconds = nextDelay ?? delay

            if usage != nil {
                freshness = fetchedAt.map { Date().timeIntervalSince($0) > 60 } == true ? .stale : .fresh
                setCachedDataReason(.rateLimited)
            } else {
                errorMessage = "ClaudeBat hit the usage endpoint rate limit"
            }

            recordMonitorEvent(
                MonitorEvent(
                    category: .fetch,
                    action: "completed",
                    trigger: trigger,
                    outcome: .rateLimited,
                    message: "usage endpoint rate limited",
                    retryAfterSeconds: nextDelay ?? delay
                )
            )

        case .noToken:
            lastFailureAt = Date()
            lastFailureReason = FetchOutcome.noToken.rawValue
            lastHTTPStatus = nil
            lastRetryAfterSeconds = nil

            if usage == nil {
                freshness = .empty
                errorMessage = nil
                setCachedDataReason(nil)
            } else {
                freshness = .stale
                setCachedDataReason(.noToken)
            }

            recordMonitorEvent(
                MonitorEvent(
                    category: .auth,
                    action: "missing_token",
                    trigger: trigger,
                    outcome: .noToken,
                    message: "token became unavailable during fetch"
                )
            )

        case .httpError(let code, _):
            lastFailureAt = Date()
            lastHTTPStatus = code
            lastRetryAfterSeconds = nil

            if code == 401 {
                lastFailureReason = FetchOutcome.http401.rawValue
                consecutiveFailures += 1
                if usage == nil {
                    errorMessage = "Claude Code auth expired. Open Claude Code and sign in again."
                } else {
                    freshness = .stale
                    setCachedDataReason(.authInvalid)
                }
                recordMonitorEvent(
                    MonitorEvent(
                        category: .auth,
                        action: "invalid_auth",
                        trigger: trigger,
                        outcome: .http401,
                        message: "usage endpoint returned 401"
                    )
                )
                if isAuthRecoveryInFlight || authRecoveryPhase == .awaitingUsageValidation {
                    recordMonitorEvent(
                        MonitorEvent(
                            category: .auth,
                            action: "usage_validation_after_refresh_failed",
                            trigger: trigger,
                            outcome: .http401,
                            message: "usage validation returned 401"
                        )
                    )
                } else {
                    Task { @MainActor in
                        await Task.yield()
                        await self.startAuthRecovery(reason: "http_401", trigger: trigger)
                    }
                }
            } else {
                lastFailureReason = FetchOutcome.httpError.rawValue
                consecutiveFailures += 1
                restartPolling(reason: "http_error_backoff")
                if usage == nil {
                    errorMessage = error.localizedDescription
                } else {
                    freshness = .stale
                    setCachedDataReason(.serverError)
                }
                recordMonitorEvent(
                    MonitorEvent(
                        category: .fetch,
                        action: "completed",
                        trigger: trigger,
                        outcome: .httpError,
                        message: "usage endpoint returned HTTP \(code)"
                    )
                )
            }

        case .networkError:
            lastFailureAt = Date()
            lastFailureReason = FetchOutcome.networkError.rawValue
            lastHTTPStatus = nil
            lastRetryAfterSeconds = nil
            consecutiveFailures += 1
            restartPolling(reason: "network_backoff")
            if usage == nil {
                errorMessage = error.localizedDescription
            } else {
                freshness = .stale
                setCachedDataReason(.networkError)
            }
            recordMonitorEvent(
                MonitorEvent(
                    category: .fetch,
                    action: "completed",
                    trigger: trigger,
                    outcome: .networkError,
                    message: error.localizedDescription
                )
            )

        case .decodingError:
            lastFailureAt = Date()
            lastFailureReason = FetchOutcome.decodingError.rawValue
            lastHTTPStatus = 200
            lastRetryAfterSeconds = nil
            consecutiveFailures += 1
            restartPolling(reason: "decoding_backoff", after: Self.decodingRetryInterval)
            if usage == nil {
                errorMessage = "ClaudeBat received an unexpected response from the usage API"
            } else {
                freshness = .stale
                setCachedDataReason(.serverError)
            }
            recordMonitorEvent(
                MonitorEvent(
                    category: .fetch,
                    action: "completed",
                    trigger: trigger,
                    outcome: .decodingError,
                    message: "usage response could not be decoded"
                )
            )
        }
    }

    private func handleUnknownError(_ error: any Error, trigger: FetchTrigger) {
        lastFailureAt = Date()
        lastFailureReason = FetchOutcome.networkError.rawValue
        lastHTTPStatus = nil
        lastRetryAfterSeconds = nil
        consecutiveFailures += 1
        restartPolling(reason: "unknown_error_backoff")
        if usage == nil {
            errorMessage = error.localizedDescription
        } else {
            freshness = .stale
            setCachedDataReason(.networkError)
        }
        recordMonitorEvent(
            MonitorEvent(
                category: .fetch,
                action: "completed",
                trigger: trigger,
                outcome: .networkError,
                message: error.localizedDescription
            )
        )
    }

    // MARK: - Monitoring Helpers

    private func sanitizedRetryAfter(_ retryAfter: TimeInterval?) -> Int {
        let delay = retryAfter ?? 300
        let safeDelay = delay < 1 ? 300 : delay
        let bufferedDelay = safeDelay + TimeInterval(Self.retryAfterBufferSeconds)
        return Int(bufferedDelay.rounded(.up))
    }

    private func prioritizedTrigger(for trigger: FetchTrigger) -> FetchTrigger {
        guard trigger != .selfHeal else { return trigger }
        guard let resetAt = usage?.fiveHour.resetsAtDate else {
            trackedResetBoundary = nil
            resetBoundaryPriorityAttempts = 0
            return trigger
        }

        if trackedResetBoundary != resetAt {
            trackedResetBoundary = resetAt
            resetBoundaryPriorityAttempts = 0
        }

        guard Date() > resetAt else { return trigger }
        guard resetBoundaryPriorityAttempts < Self.maxResetBoundaryPriorityAttempts else { return trigger }
        return .resetBoundary
    }

    private func recordResetBoundaryRequestIfNeeded(_ trigger: FetchTrigger) {
        guard trigger == .resetBoundary,
              let resetAt = usage?.fiveHour.resetsAtDate,
              Date() > resetAt else { return }

        if trackedResetBoundary != resetAt {
            trackedResetBoundary = resetAt
            resetBoundaryPriorityAttempts = 0
        }

        resetBoundaryPriorityAttempts += 1
    }

    private func clearCachedDataState() {
        let previous = cachedDataReason
        cachedDataReason = nil
        if previous != nil {
            recordMonitorEvent(
                MonitorEvent(category: .staleState, action: "cleared", message: "fresh data restored")
            )
        }
        if isAuthReason(previous) {
            recordMonitorEvent(
                MonitorEvent(category: .auth, action: "cleared", message: "auth state healthy")
            )
        }
    }

    private func setCachedDataReason(_ reason: CachedDataReason?) {
        let previous = cachedDataReason
        guard previous != reason else { return }

        cachedDataReason = reason

        if let reason {
            recordMonitorEvent(
                MonitorEvent(
                    category: .staleState,
                    action: "entered",
                    message: "rendering cached data because \(reason.rawValue)"
                )
            )
        } else {
            recordMonitorEvent(
                MonitorEvent(category: .staleState, action: "cleared", message: "stale state cleared")
            )
        }

        if isAuthReason(previous) || isAuthReason(reason) {
            recordMonitorEvent(
                MonitorEvent(
                    category: .auth,
                    action: reason == nil ? "cleared" : "changed",
                    message: reason?.rawValue ?? "auth state healthy"
                )
            )
        }
    }

    private func isAuthReason(_ reason: CachedDataReason?) -> Bool {
        reason == .authInvalid || reason == .noToken
    }

    private func shouldCoalesceWake(at date: Date) -> Bool {
        guard let lastWakeNotificationAt else { return false }
        return date.timeIntervalSince(lastWakeNotificationAt) <= wakeCoalescingWindow
    }

    private func shouldRetryAuthAfterWake401() -> Bool {
        guard let activeWakeRecoveryStartedAt else { return false }
        guard !wakeAuthRetryPending else { return false }
        guard Date().timeIntervalSince(activeWakeRecoveryStartedAt) <= Self.wakeAuthRetryGraceWindow else { return false }
        guard lastSuccessAt == nil || lastSuccessAt! < activeWakeRecoveryStartedAt else { return false }
        return true
    }

    private func clearWakeRecoveryState() {
        activeWakeRecoveryStartedAt = nil
        wakeAuthRetryPending = false
    }

    private func isOfflineErrorMessage(_ message: String?) -> Bool {
        guard let message = message?.lowercased() else { return false }
        return message.contains("not connected")
            || message.contains("internet")
            || message.contains("offline")
            || message.contains("network connection")
    }

    private func recordMonitorEvent(_ event: MonitorEvent, appRunning: Bool = true) {
        let status = makeMonitorStatus(appRunning: appRunning)
        Task {
            await monitor.record(event: event, status: status)
        }
    }

    private func rescheduleForBudgetAvailability(reason: String) async -> Int? {
        guard let nextAllowedAt = await budget.nextAllowedAt() else { return nil }
        let delay = max(1, Int(nextAllowedAt.timeIntervalSinceNow.rounded(.up)))
        await MainActor.run {
            self.restartPolling(reason: reason, after: TimeInterval(delay))
        }
        return delay
    }

    private func makeMonitorStatus(appRunning: Bool) -> MonitorStatus {
        MonitorStatus(
            pid: ProcessInfo.processInfo.processIdentifier,
            appRunning: appRunning,
            displaySleeping: displaySleeping,
            lastLaunchAt: launchedAt,
            lastAttemptAt: lastAttemptAt,
            lastSuccessAt: lastSuccessAt,
            lastFailureAt: lastFailureAt,
            lastFailureReason: lastFailureReason,
            lastHTTPStatus: lastHTTPStatus,
            consecutiveFailures: consecutiveFailures,
            currentPollIntervalSeconds: Int(activePollInterval.rounded()),
            usingCachedData: isUsingCachedData,
            cacheAgeSeconds: cacheAgeSeconds,
            sessionResetsAt: usage?.fiveHour.resetsAtDate,
            sessionRemaining: usage?.fiveHour.remainingInt,
            lastWakeAt: lastWakeAt,
            lastWakeSource: lastWakeSource,
            buildFlavor: buildInfo.buildFlavor,
            gitCommit: buildInfo.gitCommit,
            staleReason: cachedDataReason,
            cachedSessionResetAt: usage?.fiveHour.resetsAtDate,
            lastSuccessfulUsageSessionResetAt: recoverySnapshot.lastSuccessfulUsageSessionResetAt,
            lastSuccessfulAuthRefreshAt: recoverySnapshot.lastSuccessfulAuthRefreshAt,
            lastSuccessfulAuthRefreshMethod: recoverySnapshot.lastSuccessfulAuthRefreshMethod,
            lastTokenFingerprintChangedAt: recoverySnapshot.lastTokenFingerprintChangedAt,
            authRecoveryPhase: authRecoveryPhase,
            authRecoveryResult: authRecoveryResult,
            lastRecoveryAttemptAt: recoverySnapshot.lastRecoveryAttemptAt,
            lastHiddenClaudeActivationAt: recoverySnapshot.lastHiddenClaudeActivationAt
        )
    }
}
