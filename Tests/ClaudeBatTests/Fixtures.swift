import Foundation
@testable import ClaudeBatCore

extension UsageResponse {
    /// Fresh response with configurable utilization and a resetsAt 2 hours in the future.
    static func fixture(
        fiveHourUtilization: Double = 50.0,
        sevenDayUtilization: Double = 30.0,
        resetsAt: Date = Date().addingTimeInterval(7200)
    ) -> UsageResponse {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let resetsAtString = formatter.string(from: resetsAt)

        return UsageResponse(
            fiveHour: UsagePeriod(utilization: fiveHourUtilization, resetsAt: resetsAtString),
            sevenDay: UsagePeriod(utilization: sevenDayUtilization, resetsAt: resetsAtString),
            sevenDayOpus: nil,
            sevenDaySonnet: nil,
            extraUsage: nil
        )
    }

    /// Response where the 5-hour period has already reset (resetsAt in the past).
    static func expiredFixture() -> UsageResponse {
        fixture(resetsAt: Date().addingTimeInterval(-60))
    }

    /// Fixture carrying model-scoped weekly entries in the `limits` array,
    /// mirroring the post-2026-07 API shape (e.g. [("Fable", 67)]).
    static func limitsFixture(
        fiveHourUtilization: Double = 50.0,
        sevenDayUtilization: Double = 30.0,
        modelLimits: [(name: String, percent: Double)]
    ) -> UsageResponse {
        let base = fixture(fiveHourUtilization: fiveHourUtilization, sevenDayUtilization: sevenDayUtilization)
        let scoped = modelLimits.map { entry in
            UsageLimit(
                kind: "weekly_scoped",
                group: "weekly",
                percent: entry.percent,
                severity: "normal",
                resetsAt: base.sevenDay.resetsAt,
                isActive: false,
                scope: UsageLimitScope(model: UsageLimitScopeModel(id: nil, displayName: entry.name))
            )
        }
        return UsageResponse(
            fiveHour: base.fiveHour,
            sevenDay: base.sevenDay,
            limits: scoped
        )
    }
}
