import Testing
import Foundation
@testable import ClaudeBatCore

@Suite("SlidingWindowBudget")
struct SlidingWindowBudgetTests {

    @Test func fiveRequestsInWindow_blocks() async {
        let timeSource = TimeSource()
        let budget = SlidingWindowBudget(now: { timeSource.now })

        for _ in 0..<5 {
            let decision = await budget.reserveRequest(allowWindowBypass: false)
            #expect(decision == .granted)
            timeSource.now = timeSource.now.addingTimeInterval(1)
        }

        let decision = await budget.reserveRequest(allowWindowBypass: false)
        #expect(decision == .blockedByLocalWindow)
    }

    @Test func windowExpires_unblocks() async {
        let timeSource = TimeSource()
        let budget = SlidingWindowBudget(now: { timeSource.now })

        for _ in 0..<5 {
            _ = await budget.reserveRequest(allowWindowBypass: false)
        }

        // Advance past the 300s window
        timeSource.now = timeSource.now.addingTimeInterval(301)

        let decision = await budget.reserveRequest(allowWindowBypass: false)
        #expect(decision == .granted)
    }

    @Test func retryAfter_blocks() async {
        let timeSource = TimeSource()
        let budget = SlidingWindowBudget(now: { timeSource.now })

        await budget.setRetryAfter(seconds: 60)
        timeSource.now = timeSource.now.addingTimeInterval(30)

        let decision = await budget.reserveRequest(allowWindowBypass: false)
        #expect(decision == .blockedByServerCooldown)
    }

    @Test func retryAfter_expires() async {
        let timeSource = TimeSource()
        let budget = SlidingWindowBudget(now: { timeSource.now })

        await budget.setRetryAfter(seconds: 60)
        timeSource.now = timeSource.now.addingTimeInterval(61)

        let decision = await budget.reserveRequest(allowWindowBypass: false)
        #expect(decision == .granted)
    }

    @Test func isServerCooldownActive_independentOfWindow() async {
        let timeSource = TimeSource()
        let budget = SlidingWindowBudget(now: { timeSource.now })

        // Fill the window
        for _ in 0..<5 {
            _ = await budget.reserveRequest(allowWindowBypass: false)
            timeSource.now = timeSource.now.addingTimeInterval(1)
        }

        // Window is full, but no retry-after set
        let cooldown = await budget.isServerCooldownActive()
        #expect(!cooldown)
    }

    @Test func nextAllowedAt_returnsOldestPlusWindow() async {
        let startTime = Date()
        let timeSource = TimeSource(now: startTime)
        let budget = SlidingWindowBudget(now: { timeSource.now })

        for _ in 0..<5 {
            _ = await budget.reserveRequest(allowWindowBypass: false)
            timeSource.now = timeSource.now.addingTimeInterval(1)
        }

        let nextAllowed = await budget.nextAllowedAt()
        #expect(nextAllowed != nil)
        // Oldest request was at startTime, so next slot is startTime + 300
        let expected = startTime.addingTimeInterval(300)
        #expect(abs(nextAllowed!.timeIntervalSince(expected)) < 1)
    }

    @Test func nextAllowedAt_prefersRetryDate_whenLater() async {
        let startTime = Date()
        let timeSource = TimeSource(now: startTime)
        let budget = SlidingWindowBudget(now: { timeSource.now })

        for _ in 0..<5 {
            _ = await budget.reserveRequest(allowWindowBypass: false)
            timeSource.now = timeSource.now.addingTimeInterval(1)
        }

        // Set retry-after that extends beyond window expiry
        await budget.setRetryAfter(seconds: 600) // 10 minutes from current time

        let nextAllowed = await budget.nextAllowedAt()
        #expect(nextAllowed != nil)
        // Retry-after date (~startTime+5+600=605) > oldest+window (startTime+300)
        let retryExpected = timeSource.now.addingTimeInterval(600)
        #expect(abs(nextAllowed!.timeIntervalSince(retryExpected)) < 1)
    }

    @Test func bypassedRequest_stillReservesWithoutWindowAllowance() async {
        let timeSource = TimeSource()
        let budget = SlidingWindowBudget(now: { timeSource.now })

        for _ in 0..<5 {
            _ = await budget.reserveRequest(allowWindowBypass: false)
            timeSource.now = timeSource.now.addingTimeInterval(1)
        }

        let decision = await budget.reserveRequest(allowWindowBypass: true)
        #expect(decision == .granted)
        #expect(await budget.remainingBudget() == 0)
    }
}

private final class TimeSource: @unchecked Sendable {
    var now: Date

    init(now: Date = Date()) {
        self.now = now
    }
}
