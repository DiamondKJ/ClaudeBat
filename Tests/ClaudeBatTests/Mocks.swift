import Foundation
@testable import ClaudeBatCore

actor MockBudget: BudgetTracking {
    private var _allowRequests: Bool
    private var _serverCooldownActive: Bool
    private var _requestCount: Int = 0
    private var _nextAllowed: Date?
    private var _retryAfterCalled = false

    init(allowRequests: Bool = true, serverCooldownActive: Bool = false) {
        _allowRequests = allowRequests
        _serverCooldownActive = serverCooldownActive
    }

    func canRequest() -> Bool { _allowRequests && !_serverCooldownActive }
    func recordRequest() { _requestCount += 1 }
    func setRetryAfter(seconds: TimeInterval) {
        _serverCooldownActive = true
        _retryAfterCalled = true
    }
    func isServerCooldownActive() -> Bool { _serverCooldownActive }
    func nextAllowedAt() -> Date? { _nextAllowed }
    func remainingBudget() -> Int { _allowRequests ? 5 : 0 }

    // Actor-isolated accessors for test assertions
    func setAllowRequests(_ value: Bool) { _allowRequests = value }
    func setServerCooldownActive(_ value: Bool) { _serverCooldownActive = value }
    func getRequestCount() -> Int { _requestCount }
    func getRetryAfterCalled() -> Bool { _retryAfterCalled }
}

final class MockAPI: UsageFetching, @unchecked Sendable {
    var response: UsageResponse?
    var error: (any Error)?
    private(set) var fetchCount = 0

    func fetchUsage(token: String) async throws -> UsageResponse {
        fetchCount += 1
        if let error { throw error }
        return response!
    }
}

struct MockTokenProvider: TokenProvider {
    var token: String?
    func readToken() -> String? { token }
}

final class MockCache: UsageCaching, @unchecked Sendable {
    var stored: Timestamped<UsageResponse>?

    func read() -> Timestamped<UsageResponse>? { stored }
    func write(_ response: UsageResponse) {
        stored = Timestamped(value: response, fetchedAt: Date())
    }
}
