import Foundation

public protocol TokenProvider {
    func readToken() -> String?
}

public protocol UsageFetching {
    func fetchUsage(token: String) async throws -> UsageResponse
}

public protocol BudgetTracking: Actor {
    func canRequest() -> Bool
    func recordRequest()
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

public protocol AppMonitoring: Actor {
    func record(event: MonitorEvent, status: MonitorStatus)
    func latestStatus() -> MonitorStatus?
}
