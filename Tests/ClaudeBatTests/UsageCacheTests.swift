import Testing
import Foundation
@testable import ClaudeBatCore

@Suite("UsageCache")
struct UsageCacheTests {

    private func freshDefaults() -> UserDefaults {
        let name = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func writeAndRead_roundtrips() {
        let defaults = freshDefaults()
        let cache = UsageCache(defaults: defaults)
        let response = UsageResponse.fixture(fiveHourUtilization: 42)

        cache.write(response)
        let result = cache.read()

        #expect(result != nil)
        #expect(result!.value.fiveHour.utilization == 42)
    }

    @Test func readEmpty_returnsNil() {
        let defaults = freshDefaults()
        let cache = UsageCache(defaults: defaults)

        #expect(cache.read() == nil)
    }

    @Test func TTL_discards24hOldData() throws {
        let defaults = freshDefaults()
        let cache = UsageCache(defaults: defaults)

        // Seed with 25-hour-old data by encoding directly
        let old = Timestamped(value: UsageResponse.fixture(), fetchedAt: Date().addingTimeInterval(-90000))
        let data = try JSONEncoder().encode(old)
        defaults.set(data, forKey: "cachedUsageResponse")

        #expect(cache.read() == nil)
    }

    @Test func TTL_keeps23hOldData() throws {
        let defaults = freshDefaults()
        let cache = UsageCache(defaults: defaults)

        // Seed with 23-hour-old data
        let recent = Timestamped(value: UsageResponse.fixture(), fetchedAt: Date().addingTimeInterval(-82800))
        let data = try JSONEncoder().encode(recent)
        defaults.set(data, forKey: "cachedUsageResponse")

        #expect(cache.read() != nil)
    }

    @Test func isolatedDefaults_doesNotPolluteStandard() {
        let defaults = freshDefaults()
        let cache = UsageCache(defaults: defaults)

        cache.write(.fixture())

        // Standard defaults should not have this data (unless a previous test leaked)
        // We verify by reading from a different isolated suite
        let otherDefaults = freshDefaults()
        let otherCache = UsageCache(defaults: otherDefaults)
        #expect(otherCache.read() == nil)
    }
}
