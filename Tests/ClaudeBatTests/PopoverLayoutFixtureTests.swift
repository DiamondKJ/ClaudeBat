import Foundation
import Testing
@testable import ClaudeBatCore

@Suite("Popover layout fixture isolation")
struct PopoverLayoutFixtureTests {
    @MainActor
    @Test func constructorUsesOnlyDeclaredInMemoryReads() {
        let fixture = PopoverLayoutFixture.makeLayoutViewModel()

        #expect(fixture.viewModel.popoverScreen == .usage)
        #expect(fixture.probe.count(.tokenSnapshotRead) == 1)
        #expect(fixture.probe.count(.cacheRead) == 1)
        #expect(fixture.probe.count(.recoveryRead) == 1)

        let allowed: Set<LayoutFixtureOperation> = [
            .tokenSnapshotRead,
            .cacheRead,
            .recoveryRead,
        ]
        let unexpected = fixture.probe.nonzeroCounts().filter { !allowed.contains($0.key) }
        #expect(unexpected.isEmpty)
    }

    @MainActor
    @Test func pureLayoutStateAccessDoesNotReachExternalServices() {
        let fixture = PopoverLayoutFixture.makeLayoutViewModel(
            usage: PopoverLayoutFixture.expandedUsage(),
            cachedDataReason: .networkError
        )

        _ = fixture.viewModel.popoverScreen
        _ = fixture.viewModel.shouldShowCachedBanner
        _ = fixture.viewModel.isDepleted
        _ = fixture.viewModel.sessionRemaining

        for operation in [
            LayoutFixtureOperation.tokenRead,
            .tokenWrite,
            .apiFetch,
            .budgetReserve,
            .budgetMutation,
            .budgetRead,
            .cacheWrite,
            .recoveryWrite,
            .monitorRecord,
            .monitorRead,
            .authRefresh,
            .cliRecovery,
            .reachabilityRead,
        ] {
            #expect(fixture.probe.count(operation) == 0)
        }
    }

    @Test func fixedDisplayClockProducesExactResetStrings() {
        let usage = PopoverLayoutFixture.compactUsage()
        let display = PopoverLayoutFixture.displayEnvironment

        #expect(
            usage.fiveHour.timeUntilReset(
                reference: display.now,
                timeZone: display.timeZone
            ) == "Resets in 3h 59m"
        )
        #expect(
            usage.sevenDay.resetDateShort(
                reference: display.now,
                timeZone: display.timeZone
            ) == "Resets Aug 21, 6:00 PM"
        )
    }

    @Test func fixtureShapesCarryExpectedConditionalContent() {
        let compact = PopoverLayoutFixture.compactUsage()
        let expanded = PopoverLayoutFixture.expandedUsage()
        let heavy = PopoverLayoutFixture.heavyUsage()

        #expect(compact.weeklyModelBreakdown.isEmpty)
        #expect(compact.extraUsage?.isEnabled == false)
        #expect(expanded.weeklyModelBreakdown.count == 2)
        #expect(expanded.extraUsage?.isEnabled == true)
        #expect(heavy.weeklyModelBreakdown.count == 4)
        #expect(heavy.weeklyModelBreakdown[2].label == "WWWWWWWWWWWWWWWWWWWWWWWW")
    }

    @MainActor
    @Test func everyPopoverRouteHasASyntheticFixture() {
        let loading = PopoverLayoutFixture.makeLayoutViewModel(usage: nil)
        let reconnect = PopoverLayoutFixture.makeLayoutViewModel(usage: nil, tokenPresent: false)
        let error = PopoverLayoutFixture.makeLayoutViewModel(
            usage: nil,
            errorMessage: "The synthetic service returned an unexpected response."
        )
        let offline = PopoverLayoutFixture.makeLayoutViewModel(
            usage: nil,
            errorMessage: "Synthetic network connection unavailable."
        )
        let usage = PopoverLayoutFixture.makeLayoutViewModel()
        let gameOver = PopoverLayoutFixture.makeLayoutViewModel(
            usage: PopoverLayoutFixture.depletedUsage()
        )

        let expiredSnapshot = RecoverySnapshot(
            lastSuccessfulUsageAt: Date(timeIntervalSince1970: 1_786_536_000)
        )
        let recovering = PopoverLayoutFixture.makeLayoutViewModel(
            usage: PopoverLayoutFixture.expiredUsage(),
            freshness: .stale,
            cachedDataReason: .rateLimited,
            recoverySnapshot: expiredSnapshot
        )

        #expect(loading.viewModel.popoverScreen == .loading)
        #expect(reconnect.viewModel.popoverScreen == .reconnectClaude)
        #expect(error.viewModel.popoverScreen == .error)
        #expect(offline.viewModel.popoverScreen == .offline)
        #expect(usage.viewModel.popoverScreen == .usage)
        #expect(gameOver.viewModel.popoverScreen == .usage)
        #expect(gameOver.viewModel.isDepleted)
        #expect(recovering.viewModel.popoverScreen == .recovering)

        for fixture in [loading, reconnect, error, offline, usage, gameOver, recovering] {
            #expect(fixture.probe.count(.apiFetch) == 0)
            #expect(fixture.probe.count(.authRefresh) == 0)
            #expect(fixture.probe.count(.cliRecovery) == 0)
            #expect(fixture.probe.count(.monitorRecord) == 0)
        }
    }

    @MainActor
    @Test func cachedBannerReasonsAreConstructibleWithoutFetching() {
        for reason in [
            CachedDataReason.authInvalid,
            .noToken,
            .networkError,
            .serverError,
            .rateLimited,
        ] {
            let fixture = PopoverLayoutFixture.makeLayoutViewModel(cachedDataReason: reason)
            #expect(fixture.viewModel.popoverScreen == .usage)
            #expect(fixture.viewModel.shouldShowCachedBanner)
            #expect(fixture.probe.count(.apiFetch) == 0)
        }
    }

    @MainActor
    @Test func recoveryMessageVariantsAreConstructibleFromSnapshots() {
        let native = PopoverLayoutFixture.makeLayoutViewModel(
            usage: nil,
            recoverySnapshot: RecoverySnapshot(authRecoveryPhase: .nativeRefreshInFlight)
        )
        let cli = PopoverLayoutFixture.makeLayoutViewModel(
            usage: nil,
            recoverySnapshot: RecoverySnapshot(authRecoveryPhase: .claudeCLIRecoveryInFlight)
        )

        #expect(native.viewModel.recoveryMessage == "Restoring Claude Code connection.")
        #expect(cli.viewModel.recoveryMessage == "Refreshing Claude Code in the background.")
        #expect(native.probe.count(.authRefresh) == 0)
        #expect(cli.probe.count(.cliRecovery) == 0)
    }
}
