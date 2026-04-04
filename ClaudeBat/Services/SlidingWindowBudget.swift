import Foundation

/// Tracks API request budget using a sliding window.
/// Rate limit: 5 requests per 300s window.
public actor SlidingWindowBudget: BudgetTracking {
    private let maxRequests = 5
    private let windowSeconds: TimeInterval = 300
    private var timestamps: [Date] = []
    private var retryAfterDate: Date?
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    /// Can we make a request right now?
    public func canRequest() -> Bool {
        pruneExpired()

        // Respect Retry-After from 429
        if let retryDate = retryAfterDate, now() < retryDate {
            return false
        }

        return timestamps.count < maxRequests
    }

    /// Record that a request was just made.
    public func recordRequest() {
        pruneExpired()
        timestamps.append(now())
    }

    /// When is the next slot available? Returns nil if a slot is free now.
    public func nextAllowedAt() -> Date? {
        pruneExpired()

        // If in Retry-After penalty, that takes priority
        if let retryDate = retryAfterDate, now() < retryDate {
            return retryDate
        }

        guard timestamps.count >= maxRequests else { return nil }
        // Oldest request + window = when it expires and frees a slot
        return timestamps[0].addingTimeInterval(windowSeconds)
    }

    /// Set a server-imposed Retry-After cooldown.
    public func setRetryAfter(seconds: TimeInterval) {
        retryAfterDate = now().addingTimeInterval(seconds)
    }

    /// How many slots are available right now?
    public func remainingBudget() -> Int {
        pruneExpired()
        return max(0, maxRequests - timestamps.count)
    }

    /// Is the server-imposed 429 cooldown currently active?
    /// Used by bypass paths (wake, reset boundary) to always respect server limits
    /// even when bypassing the local sliding window.
    public func isServerCooldownActive() -> Bool {
        if let retryDate = retryAfterDate, now() < retryDate {
            return true
        }
        return false
    }

    private func pruneExpired() {
        let cutoff = now().addingTimeInterval(-windowSeconds)
        timestamps.removeAll { $0 < cutoff }
        // Clear expired retry-after
        if let retryDate = retryAfterDate, now() >= retryDate {
            retryAfterDate = nil
        }
    }
}
