import Testing
import Foundation
@testable import ClaudeBatCore

@Suite("UsageViewModel — Fetch Pipeline")
struct FetchPipelineTests {

    @MainActor
    @Test func successfulFetch_updatesState() async {
        let api = MockAPI()
        api.response = .fixture()
        let vm = UsageViewModel(
            tokenProvider: MockTokenProvider(token: "tok"),
            api: api,
            budget: MockBudget(),
            cache: MockCache(),
            startImmediately: false
        )

        await vm.fetchIfBudgetAllows()

        #expect(vm.usage != nil)
        #expect(vm.freshness == .fresh)
        #expect(vm.fetchedAt != nil)
        #expect(vm.errorMessage == nil)
    }

    @MainActor
    @Test func budgetExhausted_doesNotFetch() async {
        let api = MockAPI()
        api.response = .fixture()
        let vm = UsageViewModel(
            tokenProvider: MockTokenProvider(token: "tok"),
            api: api,
            budget: MockBudget(allowRequests: false),
            cache: MockCache(),
            startImmediately: false
        )

        await vm.fetchIfBudgetAllows()

        #expect(api.fetchCount == 0)
        #expect(vm.usage == nil)
    }

    @MainActor
    @Test func serverCooldown_blocksEvenBypass() async {
        let api = MockAPI()
        api.response = .fixture()
        let cache = MockCache()
        // Seed cache with expired data so hasResetBoundaryPassed = true
        cache.stored = Timestamped(value: .expiredFixture(), fetchedAt: Date())

        let vm = UsageViewModel(
            tokenProvider: MockTokenProvider(token: "tok"),
            api: api,
            budget: MockBudget(allowRequests: false, serverCooldownActive: true),
            cache: cache,
            startImmediately: false
        )

        await vm.fetchIfBudgetAllows()

        #expect(api.fetchCount == 0)
    }

    @MainActor
    @Test func tokenMissing_noCache_showsEmpty() async {
        let vm = UsageViewModel(
            tokenProvider: MockTokenProvider(token: nil),
            api: MockAPI(),
            budget: MockBudget(),
            cache: MockCache(),
            startImmediately: false
        )

        await vm.fetchIfBudgetAllows()

        #expect(vm.freshness == .empty)
        #expect(vm.errorMessage == nil)
    }

    @MainActor
    @Test func tokenMissing_withCache_showsStale() async {
        let cache = MockCache()
        cache.stored = Timestamped(value: .fixture(), fetchedAt: Date())

        let vm = UsageViewModel(
            tokenProvider: MockTokenProvider(token: nil),
            api: MockAPI(),
            budget: MockBudget(),
            cache: cache,
            startImmediately: false
        )

        await vm.fetchIfBudgetAllows()

        #expect(vm.freshness == .stale)
        #expect(vm.usage != nil)
    }

    @MainActor
    @Test func networkError_noCache_showsError() async {
        let api = MockAPI()
        api.error = UsageAPIError.networkError(URLError(.notConnectedToInternet))

        let vm = UsageViewModel(
            tokenProvider: MockTokenProvider(token: "tok"),
            api: api,
            budget: MockBudget(),
            cache: MockCache(),
            startImmediately: false
        )

        await vm.fetchIfBudgetAllows()

        #expect(vm.errorMessage != nil)
        #expect(vm.usage == nil)
    }

    @MainActor
    @Test func networkError_withCache_showsStale() async {
        let api = MockAPI()
        api.error = UsageAPIError.networkError(URLError(.notConnectedToInternet))
        let cache = MockCache()
        cache.stored = Timestamped(value: .fixture(), fetchedAt: Date())

        let vm = UsageViewModel(
            tokenProvider: MockTokenProvider(token: "tok"),
            api: api,
            budget: MockBudget(),
            cache: cache,
            startImmediately: false
        )

        await vm.fetchIfBudgetAllows()

        #expect(vm.freshness == .stale)
        #expect(vm.usage != nil)
    }

    @MainActor
    @Test func rateLimited_setsRetryAfter() async {
        let api = MockAPI()
        api.error = UsageAPIError.rateLimited(retryAfter: 60)
        let budget = MockBudget()

        let vm = UsageViewModel(
            tokenProvider: MockTokenProvider(token: "tok"),
            api: api,
            budget: budget,
            cache: MockCache(),
            startImmediately: false
        )

        await vm.fetchIfBudgetAllows()

        let called = await budget.getRetryAfterCalled()
        #expect(called)
    }

}

@Suite("UsageViewModel — Reset Boundary")
struct ResetBoundaryTests {

    @MainActor
    @Test func resetBoundaryPassed_bypassesBudget() async {
        let api = MockAPI()
        api.response = .fixture() // Fresh data with future resetsAt
        let cache = MockCache()
        // Seed with expired data — resetsAt in the past
        cache.stored = Timestamped(value: .expiredFixture(), fetchedAt: Date())

        let vm = UsageViewModel(
            tokenProvider: MockTokenProvider(token: "tok"),
            api: api,
            budget: MockBudget(allowRequests: false),
            cache: cache,
            startImmediately: false
        )

        await vm.fetchIfBudgetAllows()

        #expect(api.fetchCount == 1)
        #expect(vm.freshness == .fresh)
    }

    @MainActor
    @Test func resetBoundaryPassed_respectsServerCooldown() async {
        let api = MockAPI()
        api.response = .fixture()
        let cache = MockCache()
        cache.stored = Timestamped(value: .expiredFixture(), fetchedAt: Date())

        let vm = UsageViewModel(
            tokenProvider: MockTokenProvider(token: "tok"),
            api: api,
            budget: MockBudget(allowRequests: false, serverCooldownActive: true),
            cache: cache,
            startImmediately: false
        )

        await vm.fetchIfBudgetAllows()

        #expect(api.fetchCount == 0)
    }

    @MainActor
    @Test func freshDataClearsBoundary() async {
        let api = MockAPI()
        api.response = .fixture() // resetsAt 2h in future
        let cache = MockCache()
        cache.stored = Timestamped(value: .expiredFixture(), fetchedAt: Date())

        let budget = MockBudget(allowRequests: false)

        let vm = UsageViewModel(
            tokenProvider: MockTokenProvider(token: "tok"),
            api: api,
            budget: budget,
            cache: cache,
            startImmediately: false
        )

        // First fetch bypasses budget because reset boundary passed
        await vm.fetchIfBudgetAllows()
        #expect(api.fetchCount == 1)

        // Second fetch should NOT bypass — fresh data has future resetsAt
        await vm.fetchIfBudgetAllows()
        #expect(api.fetchCount == 1) // Still 1 — budget blocked, no bypass
    }

    @MainActor
    @Test func resetBoundaryPriorityDemotesAfterTwoNetworkAttempts() async {
        let api = MockAPI()
        api.error = UsageAPIError.rateLimited(retryAfter: 60)
        let cache = MockCache()
        cache.stored = Timestamped(value: .expiredFixture(), fetchedAt: Date())
        let budget = MockBudget(allowRequests: true)
        let monitor = MockMonitor()

        let vm = UsageViewModel(
            tokenProvider: MockTokenProvider(token: "tok"),
            api: api,
            budget: budget,
            cache: cache,
            monitor: monitor,
            startImmediately: false
        )

        await vm.fetchIfBudgetAllows(trigger: .pollTimer)
        await budget.setServerCooldownActive(false)
        await budget.setAllowRequests(true)
        await budget.setNextAllowed(nil)

        await vm.fetchIfBudgetAllows(trigger: .pollTimer)
        await budget.setServerCooldownActive(false)
        await budget.setAllowRequests(false)
        await budget.setNextAllowed(nil)

        await vm.fetchIfBudgetAllows(trigger: .pollTimer)
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(api.fetchCount == 2)
        #expect(await monitor.containsEvent(category: .fetch, action: "blocked", trigger: .pollTimer, outcome: .budgetBlocked))
    }
}

@Suite("UsageViewModel — Rate Limit Handling")
struct RateLimitTests {

    @MainActor
    @Test func retryAfter_zero_clampsToDefault() async {
        let api = MockAPI()
        api.error = UsageAPIError.rateLimited(retryAfter: 0.0)
        let budget = MockBudget()
        let monitor = MockMonitor()

        let vm = UsageViewModel(
            tokenProvider: MockTokenProvider(token: "tok"),
            api: api,
            budget: budget,
            cache: MockCache(),
            monitor: monitor,
            startImmediately: false
        )

        await vm.fetchIfBudgetAllows()
        try? await Task.sleep(nanoseconds: 50_000_000)

        let called = await budget.getRetryAfterCalled()
        #expect(called)
        let status = await monitor.latestStatus()
        #expect(status?.currentPollIntervalSeconds ?? 0 >= 300)
    }
}

@Suite("UsageViewModel — Monitoring")
struct UsageViewModelMonitoringTests {

    @MainActor
    @Test func http401_withCache_marksAuthInvalidAndRecordsMonitorState() async {
        let api = MockAPI()
        api.error = UsageAPIError.httpError(401, "unauthorized")
        let cache = MockCache()
        cache.stored = Timestamped(value: .fixture(), fetchedAt: Date())
        let monitor = MockMonitor()

        let vm = UsageViewModel(
            tokenProvider: MockTokenProvider(token: "tok"),
            api: api,
            budget: MockBudget(),
            cache: cache,
            monitor: monitor,
            buildInfo: AppBuildInfo(appVersion: "1.0.7", buildFlavor: "local-monitor", gitCommit: "abc1234", bundleIdentifier: "com.diamondkj.claudebat"),
            startImmediately: false
        )

        await vm.fetchIfBudgetAllows(trigger: .pollTimer)

        #expect(vm.cachedDataReason == .authInvalid)
        #expect(await monitor.containsEvent(category: .auth, action: "invalid_auth", outcome: .http401))
        let status = await monitor.latestStatus()
        #expect(status?.staleReason == .authInvalid)
        #expect(status?.usingCachedData == true)
    }

    @MainActor
    @Test func networkError_withCache_marksCachedDataState() async {
        let api = MockAPI()
        api.error = UsageAPIError.networkError(URLError(.notConnectedToInternet))
        let cache = MockCache()
        cache.stored = Timestamped(value: .fixture(), fetchedAt: Date())
        let monitor = MockMonitor()

        let vm = UsageViewModel(
            tokenProvider: MockTokenProvider(token: "tok"),
            api: api,
            budget: MockBudget(),
            cache: cache,
            monitor: monitor,
            startImmediately: false
        )

        await vm.fetchIfBudgetAllows(trigger: .pollTimer)

        #expect(vm.cachedDataReason == .networkError)
        #expect(await monitor.containsEvent(category: .staleState, action: "entered"))
        let status = await monitor.latestStatus()
        #expect(status?.staleReason == .networkError)
        #expect(status?.usingCachedData == true)
    }

    @MainActor
    @Test func tokenMissing_withCache_marksNoToken() async {
        let cache = MockCache()
        cache.stored = Timestamped(value: .fixture(), fetchedAt: Date())
        let monitor = MockMonitor()

        let vm = UsageViewModel(
            tokenProvider: MockTokenProvider(token: nil),
            api: MockAPI(),
            budget: MockBudget(),
            cache: cache,
            monitor: monitor,
            startImmediately: false
        )

        await vm.fetchIfBudgetAllows(trigger: .pollTimer)
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(vm.cachedDataReason == .noToken)
        #expect(await monitor.containsEvent(category: .auth, action: "missing_token", outcome: .noToken))
    }

    @MainActor
    @Test func budgetBlocked_recordsBlockedFetchEvent() async {
        let api = MockAPI()
        api.response = .fixture()
        let monitor = MockMonitor()

        let vm = UsageViewModel(
            tokenProvider: MockTokenProvider(token: "tok"),
            api: api,
            budget: MockBudget(allowRequests: false),
            cache: MockCache(),
            monitor: monitor,
            startImmediately: false
        )

        await vm.fetchIfBudgetAllows(trigger: .pollTimer)
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(await monitor.containsEvent(category: .fetch, action: "blocked", outcome: .budgetBlocked))
    }

    @MainActor
    @Test func rateLimited_withCache_recordsRetryAfterState() async {
        let api = MockAPI()
        api.error = UsageAPIError.rateLimited(retryAfter: 60)
        let cache = MockCache()
        cache.stored = Timestamped(value: .fixture(), fetchedAt: Date())
        let monitor = MockMonitor()

        let vm = UsageViewModel(
            tokenProvider: MockTokenProvider(token: "tok"),
            api: api,
            budget: MockBudget(),
            cache: cache,
            monitor: monitor,
            startImmediately: false
        )

        await vm.fetchIfBudgetAllows(trigger: .pollTimer)
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(vm.cachedDataReason == .rateLimited)
        #expect(await monitor.containsEvent(category: .fetch, action: "completed", outcome: .rateLimited))
        let status = await monitor.latestStatus()
        #expect(status?.lastHTTPStatus == 429)
        #expect(status?.currentPollIntervalSeconds ?? 0 >= 65)
    }

    @MainActor
    @Test func serverCooldownBlocked_reschedulesNextPollAtCooldownBoundary() async {
        let api = MockAPI()
        let cache = MockCache()
        cache.stored = Timestamped(value: .fixture(), fetchedAt: Date())
        let monitor = MockMonitor()
        let budget = MockBudget(
            allowRequests: true,
            serverCooldownActive: true,
            nextAllowed: Date().addingTimeInterval(90)
        )

        let vm = UsageViewModel(
            tokenProvider: MockTokenProvider(token: "tok"),
            api: api,
            budget: budget,
            cache: cache,
            monitor: monitor,
            startImmediately: false
        )

        await vm.fetchIfBudgetAllows(trigger: .pollTimer)
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(api.fetchCount == 0)
        #expect(await monitor.containsEvent(category: .fetch, action: "blocked", outcome: .serverCooldownBlocked))
        let status = await monitor.latestStatus()
        #expect(status?.currentPollIntervalSeconds ?? 0 >= 85)
    }

    @MainActor
    @Test func decodingError_withCache_usesShortRetryAndMarksServerStale() async {
        let api = MockAPI()
        api.error = UsageAPIError.decodingError(
            DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad payload")),
            "{\"seven_day\":null}"
        )
        let cache = MockCache()
        cache.stored = Timestamped(value: .fixture(), fetchedAt: Date())
        let monitor = MockMonitor()

        let vm = UsageViewModel(
            tokenProvider: MockTokenProvider(token: "tok"),
            api: api,
            budget: MockBudget(),
            cache: cache,
            monitor: monitor,
            startImmediately: false
        )

        await vm.fetchIfBudgetAllows(trigger: .pollTimer)
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(vm.cachedDataReason == .serverError)
        let status = await monitor.latestStatus()
        #expect(status?.lastFailureReason == FetchOutcome.decodingError.rawValue)
        #expect(status?.currentPollIntervalSeconds == 60)
    }

    @MainActor
    @Test func handleWake_recordsWakeAndFetchAttempt() async {
        let api = MockAPI()
        api.response = .fixture()
        let cache = MockCache()
        cache.stored = Timestamped(value: .fixture(), fetchedAt: Date().addingTimeInterval(-400))
        let monitor = MockMonitor()

        let vm = UsageViewModel(
            tokenProvider: MockTokenProvider(token: "tok"),
            api: api,
            budget: MockBudget(),
            cache: cache,
            monitor: monitor,
            startImmediately: false
        )

        vm.handleWake(source: .machine)
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(api.fetchCount == 1)
        #expect(await monitor.containsEvent(category: .lifecycle, action: "wake_observed"))
        #expect(await monitor.containsEvent(category: .fetch, action: "started", trigger: .machineWake))
    }

    @MainActor
    @Test func duplicateWakeNotifications_areCoalescedIntoSingleRecovery() async {
        let api = MockAPI()
        api.response = .fixture()
        let cache = MockCache()
        cache.stored = Timestamped(value: .fixture(), fetchedAt: Date().addingTimeInterval(-400))
        let monitor = MockMonitor()

        let vm = UsageViewModel(
            tokenProvider: MockTokenProvider(token: "tok"),
            api: api,
            budget: MockBudget(),
            cache: cache,
            monitor: monitor,
            startImmediately: false
        )

        vm.handleWake(source: .screen)
        vm.handleWake(source: .machine)
        try? await Task.sleep(nanoseconds: 150_000_000)

        #expect(api.fetchCount == 1)
        #expect(await monitor.countEvents(category: .fetch, action: "started") == 1)
        #expect(await monitor.containsEvent(category: .lifecycle, action: "wake_coalesced"))
    }

    @MainActor
    @Test func firstWake401_retriesBeforeShowingReconnect() async {
        let api = MockAPI()
        api.queuedResults = [
            .failure(UsageAPIError.httpError(401, "unauthorized")),
            .success(.fixture())
        ]
        let cache = MockCache()
        cache.stored = Timestamped(value: .fixture(), fetchedAt: Date().addingTimeInterval(-400))
        let monitor = MockMonitor()

        let vm = UsageViewModel(
            tokenProvider: MockTokenProvider(token: "tok"),
            api: api,
            budget: MockBudget(),
            cache: cache,
            monitor: monitor,
            wakeAuthRetryInterval: 1,
            startImmediately: false
        )

        vm.handleWake(source: .machine)
        try? await Task.sleep(nanoseconds: 150_000_000)

        #expect(api.fetchCount == 1)
        #expect(vm.cachedDataReason != .authInvalid)
        #expect(vm.popoverScreen == .recovering)
        #expect(vm.shouldShowMenuBarUsage == false)
        #expect(await monitor.containsEvent(category: .auth, action: "retrying_after_wake", outcome: .http401))

        try? await Task.sleep(nanoseconds: 1_100_000_000)

        #expect(api.fetchCount == 2)
        #expect(vm.cachedDataReason == nil)
        #expect(vm.popoverScreen == .usage)
        #expect(vm.shouldShowMenuBarUsage == true)
    }

    @MainActor
    @Test func popoverOpen_usesConservativePollingCadence() async {
        let monitor = MockMonitor()

        let vm = UsageViewModel(
            tokenProvider: MockTokenProvider(token: "tok"),
            api: MockAPI(),
            budget: MockBudget(),
            cache: MockCache(),
            monitor: monitor,
            startImmediately: false
        )

        vm.onPopoverOpen()
        try? await Task.sleep(nanoseconds: 50_000_000)

        let status = await monitor.latestStatus()
        #expect(status?.currentPollIntervalSeconds == 120)
    }
}

@Suite("UsageViewModel — Popover Routing")
struct UsageViewModelPopoverRoutingTests {

    @MainActor
    @Test func expiredCachedSession_withoutFailureRoutesToRecovering() async {
        let cache = MockCache()
        cache.stored = Timestamped(value: .expiredFixture(), fetchedAt: Date().addingTimeInterval(-3600))

        let vm = UsageViewModel(
            tokenProvider: MockTokenProvider(token: "tok"),
            api: MockAPI(),
            budget: MockBudget(),
            cache: cache,
            startImmediately: false
        )

        #expect(vm.sessionDataNeedsRefresh)
        #expect(vm.popoverScreen == .recovering)
        #expect(vm.shouldShowMenuBarUsage == false)
    }

    @MainActor
    @Test func expiredCachedSession_authFailureRoutesToReconnect() async {
        let api = MockAPI()
        api.error = UsageAPIError.httpError(401, "unauthorized")
        let cache = MockCache()
        cache.stored = Timestamped(value: .expiredFixture(), fetchedAt: Date().addingTimeInterval(-3600))

        let vm = UsageViewModel(
            tokenProvider: MockTokenProvider(token: "tok"),
            api: api,
            budget: MockBudget(),
            cache: cache,
            startImmediately: false
        )

        await vm.fetchIfBudgetAllows(trigger: .pollTimer)

        #expect(vm.popoverScreen == .reconnectClaude)
        #expect(vm.authPrompt == .reconnect)
    }

    @MainActor
    @Test func expiredCachedSession_networkFailureRoutesToOffline() async {
        let api = MockAPI()
        api.error = UsageAPIError.networkError(URLError(.notConnectedToInternet))
        let cache = MockCache()
        cache.stored = Timestamped(value: .expiredFixture(), fetchedAt: Date().addingTimeInterval(-3600))

        let vm = UsageViewModel(
            tokenProvider: MockTokenProvider(token: "tok"),
            api: api,
            budget: MockBudget(),
            cache: cache,
            startImmediately: false
        )

        await vm.fetchIfBudgetAllows(trigger: .pollTimer)

        #expect(vm.popoverScreen == .offline)
    }

    @MainActor
    @Test func expiredCachedSession_rateLimitRoutesToRecovering() async {
        let api = MockAPI()
        api.error = UsageAPIError.rateLimited(retryAfter: 60)
        let cache = MockCache()
        cache.stored = Timestamped(value: .expiredFixture(), fetchedAt: Date().addingTimeInterval(-3600))

        let vm = UsageViewModel(
            tokenProvider: MockTokenProvider(token: "tok"),
            api: api,
            budget: MockBudget(),
            cache: cache,
            startImmediately: false
        )

        await vm.fetchIfBudgetAllows(trigger: .pollTimer)

        #expect(vm.popoverScreen == .recovering)
    }

    @MainActor
    @Test func freshCachedSession_networkFailureKeepsUsageScreen() async {
        let api = MockAPI()
        api.error = UsageAPIError.networkError(URLError(.notConnectedToInternet))
        let cache = MockCache()
        cache.stored = Timestamped(value: .fixture(), fetchedAt: Date())

        let vm = UsageViewModel(
            tokenProvider: MockTokenProvider(token: "tok"),
            api: api,
            budget: MockBudget(),
            cache: cache,
            startImmediately: false
        )

        await vm.fetchIfBudgetAllows(trigger: .pollTimer)

        #expect(vm.popoverScreen == .usage)
        #expect(vm.shouldShowCachedBanner)
    }
}
