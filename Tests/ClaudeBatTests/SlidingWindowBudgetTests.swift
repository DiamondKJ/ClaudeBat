import Testing
import Foundation
@testable import ClaudeBatCore

@Suite("SlidingWindowBudget")
struct SlidingWindowBudgetTests {

    @Test func fiveRequestsInWindow_blocks() async {
        var time = Date()
        let budget = SlidingWindowBudget(now: { time })

        for _ in 0..<5 {
            await budget.recordRequest()
            time = time.addingTimeInterval(1)
        }

        let canGo = await budget.canRequest()
        #expect(!canGo)
    }

    @Test func windowExpires_unblocks() async {
        var time = Date()
        let budget = SlidingWindowBudget(now: { time })

        for _ in 0..<5 {
            await budget.recordRequest()
        }

        // Advance past the 300s window
        time = time.addingTimeInterval(301)

        let canGo = await budget.canRequest()
        #expect(canGo)
    }

    @Test func retryAfter_blocks() async {
        var time = Date()
        let budget = SlidingWindowBudget(now: { time })

        await budget.setRetryAfter(seconds: 60)
        time = time.addingTimeInterval(30)

        let canGo = await budget.canRequest()
        #expect(!canGo)
    }

    @Test func retryAfter_expires() async {
        var time = Date()
        let budget = SlidingWindowBudget(now: { time })

        await budget.setRetryAfter(seconds: 60)
        time = time.addingTimeInterval(61)

        let canGo = await budget.canRequest()
        #expect(canGo)
    }

    @Test func isServerCooldownActive_independentOfWindow() async {
        var time = Date()
        let budget = SlidingWindowBudget(now: { time })

        // Fill the window
        for _ in 0..<5 {
            await budget.recordRequest()
            time = time.addingTimeInterval(1)
        }

        // Window is full, but no retry-after set
        let cooldown = await budget.isServerCooldownActive()
        #expect(!cooldown)
    }

    @Test func nextAllowedAt_returnsOldestPlusWindow() async {
        let startTime = Date()
        var time = startTime
        let budget = SlidingWindowBudget(now: { time })

        for _ in 0..<5 {
            await budget.recordRequest()
            time = time.addingTimeInterval(1)
        }

        let nextAllowed = await budget.nextAllowedAt()
        #expect(nextAllowed != nil)
        // Oldest request was at startTime, so next slot is startTime + 300
        let expected = startTime.addingTimeInterval(300)
        #expect(abs(nextAllowed!.timeIntervalSince(expected)) < 1)
    }

    @Test func nextAllowedAt_prefersRetryDate_whenLater() async {
        let startTime = Date()
        var time = startTime
        let budget = SlidingWindowBudget(now: { time })

        for _ in 0..<5 {
            await budget.recordRequest()
            time = time.addingTimeInterval(1)
        }

        // Set retry-after that extends beyond window expiry
        await budget.setRetryAfter(seconds: 600) // 10 minutes from current time

        let nextAllowed = await budget.nextAllowedAt()
        #expect(nextAllowed != nil)
        // Retry-after date (~startTime+5+600=605) > oldest+window (startTime+300)
        let retryExpected = time.addingTimeInterval(600)
        #expect(abs(nextAllowed!.timeIntervalSince(retryExpected)) < 1)
    }
}
