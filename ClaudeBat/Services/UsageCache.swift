import Foundation

/// Wraps a value with its fetch timestamp for staleness tracking.
public struct Timestamped<T: Codable>: Codable {
    public let value: T
    public let fetchedAt: Date

    public init(value: T, fetchedAt: Date) {
        self.value = value
        self.fetchedAt = fetchedAt
    }

    public var age: TimeInterval { Date().timeIntervalSince(fetchedAt) }
}

/// Single-response cache backed by UserDefaults.
/// Survives app restart. Loads synchronously for instant menu bar display.
public struct UsageCache: UsageCaching {
    private let defaults: UserDefaults
    private static let key = "cachedUsageResponse"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func read() -> Timestamped<UsageResponse>? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        guard let stamped = try? JSONDecoder().decode(Timestamped<UsageResponse>.self, from: data) else { return nil }
        guard stamped.age <= 86400 else { return nil }  // 24h TTL
        return stamped
    }

    public func write(_ response: UsageResponse) {
        let stamped = Timestamped(value: response, fetchedAt: Date())
        if let data = try? JSONEncoder().encode(stamped) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
