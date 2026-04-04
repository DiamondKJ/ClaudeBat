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
}

@Suite("UsageViewModel — Rate Limit Handling")
struct RateLimitTests {

    @MainActor
    @Test func retryAfter_zero_clampsToDefault() async {
        let api = MockAPI()
        api.error = UsageAPIError.rateLimited(retryAfter: 0.0)
        let budget = MockBudget()

        let vm = UsageViewModel(
            tokenProvider: MockTokenProvider(token: "tok"),
            api: api,
            budget: budget,
            cache: MockCache(),
            startImmediately: false
        )

        await vm.fetchIfBudgetAllows()

        // retryAfter: 0.0 should be clamped — setRetryAfter still called
        let called = await budget.getRetryAfterCalled()
        #expect(called)
    }
}
