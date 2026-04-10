import Testing
import Foundation
@testable import ClaudeBatCore

@Suite("UsageModels")
struct UsageModelsTests {

    @Test(arguments: [0.0, 25.0, 50.0, 75.0, 100.0])
    func remainingCalculation(utilization: Double) {
        let period = UsagePeriod(utilization: utilization, resetsAt: "2026-04-04T12:00:00.000Z")
        let expected = 100 - utilization
        #expect(period.remaining == expected)
        #expect(period.remainingInt == Int(expected.rounded()))
    }

    @Test func isFullyMaxed_requiresBothZero() {
        let maxed = UsageResponse.fixture(fiveHourUtilization: 100, sevenDayUtilization: 100)
        let fiveOnly = UsageResponse.fixture(fiveHourUtilization: 100, sevenDayUtilization: 50)
        let sevenOnly = UsageResponse.fixture(fiveHourUtilization: 50, sevenDayUtilization: 100)
        let neither = UsageResponse.fixture(fiveHourUtilization: 50, sevenDayUtilization: 50)

        // isFullyMaxed is on the ViewModel, so test the underlying logic directly
        #expect(maxed.fiveHour.remaining <= 0 && maxed.sevenDay.remaining <= 0)
        #expect(!(fiveOnly.fiveHour.remaining <= 0 && fiveOnly.sevenDay.remaining <= 0))
        #expect(!(sevenOnly.fiveHour.remaining <= 0 && sevenOnly.sevenDay.remaining <= 0))
        #expect(!(neither.fiveHour.remaining <= 0 && neither.sevenDay.remaining <= 0))
    }

    @Test func timeUntilReset_pastDate_returnsRecentlyReset() {
        let past = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-60))
        let period = UsagePeriod(utilization: 50, resetsAt: past)
        #expect(period.timeUntilReset == "Recently reset")
    }

    @Test func timeUntilReset_futureDate_returnsCountdown() {
        let future = ISO8601DateFormatter().string(from: Date().addingTimeInterval(5400))
        let period = UsagePeriod(utilization: 50, resetsAt: future)
        let result = period.timeUntilReset
        #expect(result.hasPrefix("Resets in 1h"))
    }

    @Test func decodesNullableFiveHourReset() throws {
        let payload = """
        {
          "five_hour": { "utilization": 0.0, "resets_at": null },
          "seven_day": { "utilization": 76.0, "resets_at": "2026-04-12T19:00:00.351655+00:00" },
          "seven_day_sonnet": { "utilization": 23.0, "resets_at": "2026-04-13T09:00:00.351668+00:00" },
          "seven_day_opus": null,
          "extra_usage": { "is_enabled": true, "monthly_limit": 3750, "used_credits": 0.0, "utilization": null }
        }
        """

        let decoded = try JSONDecoder().decode(UsageResponse.self, from: Data(payload.utf8))

        #expect(decoded.fiveHour.resetsAt == nil)
        #expect(decoded.fiveHour.resetsAtDate == nil)
        #expect(decoded.fiveHour.remainingInt == 100)
        #expect(decoded.sevenDay.resetsAtDate != nil)
    }
}
