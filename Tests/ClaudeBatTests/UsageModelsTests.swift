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

    @Test func depleted_whenEitherLimitZero() {
        let both = UsageResponse.fixture(fiveHourUtilization: 100, sevenDayUtilization: 100)
        let fiveOnly = UsageResponse.fixture(fiveHourUtilization: 100, sevenDayUtilization: 50)
        let sevenOnly = UsageResponse.fixture(fiveHourUtilization: 50, sevenDayUtilization: 100)
        let neither = UsageResponse.fixture(fiveHourUtilization: 50, sevenDayUtilization: 50)

        // Mirrors UsageViewModel.isDepleted: blocked when EITHER limit is exhausted.
        func depleted(_ u: UsageResponse) -> Bool {
            u.fiveHour.remaining <= 0 || u.sevenDay.remaining <= 0
        }
        #expect(depleted(both))
        #expect(depleted(fiveOnly))
        #expect(depleted(sevenOnly))
        #expect(!depleted(neither))
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

    @Test func formatResetTimestamp_consistentAndLocaleStable() {
        let now = Date()
        let sameDay = now.addingTimeInterval(3 * 3600)        // 3h out
        let farOff = now.addingTimeInterval(3 * 24 * 3600)    // 3 days out

        let sameDayStr = UsagePeriod.formatResetTimestamp(sameDay, reference: now)
        let farOffStr = UsagePeriod.formatResetTimestamp(farOff, reference: now)

        // Same-day: time only — no date/comma.
        #expect(!sameDayStr.contains(","))
        #expect(sameDayStr.contains(":"))
        // Far-off: dated form with a comma between date and time.
        #expect(farOffStr.contains(","))
        // Both en_US_POSIX (locale-stable) — AM/PM regardless of the host locale.
        #expect(sameDayStr.contains("AM") || sameDayStr.contains("PM"))
        #expect(farOffStr.contains("AM") || farOffStr.contains("PM"))
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

    @Test func decodesLimitsArray_post2026Shape() throws {
        // Trimmed from a real /usage response captured 2026-07-12: the legacy
        // per-model buckets are null and model usage lives in `limits`.
        let payload = """
        {
          "five_hour": { "utilization": 90.0, "resets_at": "2026-07-12T20:50:00.798305+00:00" },
          "seven_day": { "utilization": 57.0, "resets_at": "2026-07-18T18:00:00.798328+00:00" },
          "seven_day_opus": null,
          "seven_day_sonnet": null,
          "iguana_necktie": null,
          "extra_usage": { "is_enabled": false },
          "limits": [
            { "kind": "session", "group": "session", "percent": 90, "severity": "critical", "resets_at": "2026-07-12T20:50:00.798305+00:00", "scope": null, "is_active": true },
            { "kind": "weekly_all", "group": "weekly", "percent": 57, "severity": "normal", "resets_at": "2026-07-18T18:00:00.798328+00:00", "scope": null, "is_active": false },
            { "kind": "weekly_scoped", "group": "weekly", "percent": 67, "severity": "normal", "resets_at": "2026-07-18T17:59:59.798634+00:00", "scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null }, "is_active": false }
          ]
        }
        """

        let decoded = try JSONDecoder().decode(UsageResponse.self, from: Data(payload.utf8))

        #expect(decoded.limits?.count == 3)
        let breakdown = decoded.weeklyModelBreakdown
        #expect(breakdown.count == 1)
        #expect(breakdown.first?.label == "Fable")
        #expect(breakdown.first?.period.remainingInt == 33)
        #expect(breakdown.first?.period.resetsAtDate != nil)
    }

    @Test func weeklyModelBreakdown_multipleScopedModels() {
        let response = UsageResponse.limitsFixture(modelLimits: [("Fable", 67), ("Sonnet", 20)])
        let breakdown = response.weeklyModelBreakdown

        #expect(breakdown.map(\.label) == ["Fable", "Sonnet"])
        #expect(breakdown.map(\.period.remainingInt) == [33, 80])
    }

    @Test func weeklyModelBreakdown_ignoresUnscopedAndNonWeeklyLimits() {
        let response = UsageResponse(
            fiveHour: UsagePeriod(utilization: 10, resetsAt: nil),
            sevenDay: UsagePeriod(utilization: 10, resetsAt: nil),
            limits: [
                UsageLimit(kind: "session", group: "session", percent: 90,
                           scope: UsageLimitScope(model: UsageLimitScopeModel(displayName: "Fable"))),
                UsageLimit(kind: "weekly_all", group: "weekly", percent: 57, scope: nil),
            ]
        )
        #expect(response.weeklyModelBreakdown.isEmpty)
    }

    @Test func weeklyModelBreakdown_fallsBackToLegacyBuckets() {
        let legacy = UsageResponse(
            fiveHour: UsagePeriod(utilization: 10, resetsAt: nil),
            sevenDay: UsagePeriod(utilization: 10, resetsAt: nil),
            sevenDayOpus: UsagePeriod(utilization: 40, resetsAt: nil),
            sevenDaySonnet: UsagePeriod(utilization: 23, resetsAt: nil)
        )
        let breakdown = legacy.weeklyModelBreakdown

        #expect(breakdown.map(\.label) == ["Opus", "Sonnet"])
        #expect(breakdown.map(\.period.remainingInt) == [60, 77])
    }

    @Test func weeklyModelBreakdown_emptyWhenNoModelData() {
        #expect(UsageResponse.fixture().weeklyModelBreakdown.isEmpty)
    }
}
