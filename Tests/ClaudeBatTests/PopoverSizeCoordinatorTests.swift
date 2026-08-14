import CoreGraphics
import Testing
@testable import ClaudeBatCore

@MainActor
private final class ManualPopoverScheduler {
    private(set) var work: [PopoverSizeCoordinator.ScheduledWork] = []

    func schedule(_ item: @escaping PopoverSizeCoordinator.ScheduledWork) {
        work.append(item)
    }

    func run(at index: Int = 0) {
        let item = work.remove(at: index)
        item()
    }
}

@MainActor
private final class CoordinatorIO {
    var measured = CGSize(width: 320, height: 392)
    var current: CGSize? = CGSize(width: 320, height: 392)
    var measurementSequence: [CGSize] = []
    var applications: [CGSize] = []
    var applyResult = true
    var onMeasure: (() -> Void)?
    var onRead: (() -> Void)?
    var onApply: ((CGSize) -> Void)?

    func nextMeasurement() -> CGSize? {
        onMeasure?()
        if !measurementSequence.isEmpty {
            return measurementSequence.removeFirst()
        }
        return measured
    }

    func readCurrent() -> CGSize? {
        onRead?()
        return current
    }

    func apply(_ size: CGSize) -> Bool {
        applications.append(size)
        if applyResult {
            current = size
        }
        onApply?(size)
        return applyResult
    }
}

@MainActor
private func makeCoordinator(
    io: CoordinatorIO,
    scheduler: ManualPopoverScheduler
) -> PopoverSizeCoordinator {
    PopoverSizeCoordinator(
        width: 320,
        measure: { [weak io] in io?.nextMeasurement() },
        readCurrentSize: { [weak io] in io?.readCurrent() },
        applySize: { [weak io] size in io?.apply(size) ?? false },
        scheduler: { [weak scheduler] work in scheduler?.schedule(work) }
    )
}

@MainActor
private func prepareAndShow(_ coordinator: PopoverSizeCoordinator) throws -> PopoverSizeCoordinator.Session {
    let session = try #require(coordinator.beginPresentation())
    try #require(coordinator.prepareForShow(in: session))
    coordinator.markShown(in: session)
    return session
}

@Suite("PopoverSizeCoordinator", .serialized)
struct PopoverSizeCoordinatorTests {
    @MainActor
    @Test func preflightNormalizesHeightAndCorrectsWidthSynchronously() throws {
        let io = CoordinatorIO()
        let scheduler = ManualPopoverScheduler()
        io.measured = CGSize(width: 319, height: 391.74)
        io.current = CGSize(width: 319, height: 391.5)
        let coordinator = makeCoordinator(io: io, scheduler: scheduler)
        let session = try #require(coordinator.beginPresentation())

        #expect(coordinator.prepareForShow(in: session))
        #expect(io.applications == [CGSize(width: 320, height: 391.5)])
        #expect(scheduler.work.isEmpty)

        coordinator.markShown(in: session)
        coordinator.contentMayHaveChanged(in: session)
        #expect(scheduler.work.count == 1)
    }

    @MainActor
    @Test func malformedMeasurementsFailClosed() throws {
        let invalidHeights: [CGFloat] = [
            .nan,
            -.infinity,
            0,
            0.1,
            0.24,
            .greatestFiniteMagnitude,
        ]

        for height in invalidHeights {
            let io = CoordinatorIO()
            let scheduler = ManualPopoverScheduler()
            io.measured = CGSize(width: 320, height: height)
            let coordinator = makeCoordinator(io: io, scheduler: scheduler)
            let session = try #require(coordinator.beginPresentation())
            #expect(!coordinator.prepareForShow(in: session))
            #expect(io.applications.isEmpty)
            coordinator.markShown(in: session)
            coordinator.contentMayHaveChanged(in: session)
            #expect(scheduler.work.isEmpty)
        }

        #expect(PopoverSizeCoordinator.normalizedHeight(0.25) == 0.5)
        #expect(PopoverSizeCoordinator.normalizedHeight(0.24) == nil)
    }

    @MainActor
    @Test func tenThousandStableInvalidationsCoalesceToOneNoOpDrain() throws {
        let io = CoordinatorIO()
        let scheduler = ManualPopoverScheduler()
        let coordinator = makeCoordinator(io: io, scheduler: scheduler)
        let session = try prepareAndShow(coordinator)
        let before = coordinator.debugCounters

        for _ in 0..<10_000 {
            coordinator.contentMayHaveChanged(in: session)
        }

        #expect(scheduler.work.count == 1)
        #expect(coordinator.debugCounters.scheduledDrains - before.scheduledDrains == 1)
        scheduler.run()
        #expect(coordinator.debugCounters.drains - before.drains == 1)
        #expect(coordinator.debugCounters.measurements - before.measurements == 1)
        #expect(coordinator.debugCounters.sinkCalls - before.sinkCalls == 0)
        #expect(coordinator.debugCounters.maxPendingTargets == 1)
        #expect(io.applications.isEmpty)
    }

    @MainActor
    @Test func oneBurstMeasuresNewestContentAndWritesOnce() throws {
        let io = CoordinatorIO()
        let scheduler = ManualPopoverScheduler()
        let coordinator = makeCoordinator(io: io, scheduler: scheduler)
        let session = try prepareAndShow(coordinator)

        coordinator.contentMayHaveChanged(in: session)
        io.measured = CGSize(width: 320, height: 421)
        for _ in 0..<1_000 {
            coordinator.contentMayHaveChanged(in: session)
        }

        #expect(scheduler.work.count == 1)
        scheduler.run()
        #expect(io.applications == [CGSize(width: 320, height: 421)])
    }

    @MainActor
    @Test func staleDrainCannotConsumeNewSessionWorkInEitherOrder() throws {
        for runNewFirst in [false, true] {
            let io = CoordinatorIO()
            let scheduler = ManualPopoverScheduler()
            let coordinator = makeCoordinator(io: io, scheduler: scheduler)
            let first = try prepareAndShow(coordinator)

            io.measured = CGSize(width: 320, height: 421)
            coordinator.contentMayHaveChanged(in: first)
            coordinator.endPresentation(first)

            io.measured = CGSize(width: 320, height: 392)
            let second = try prepareAndShow(coordinator)
            io.measured = CGSize(width: 320, height: 470)
            coordinator.contentMayHaveChanged(in: second)
            #expect(scheduler.work.count == 2)

            scheduler.run(at: runNewFirst ? 1 : 0)
            scheduler.run()
            #expect(io.current == CGSize(width: 320, height: 470))
            #expect(io.applications.last == CGSize(width: 320, height: 470))
        }
    }

    @MainActor
    @Test func staleExternalSessionCallsCannotAffectCurrentSession() throws {
        let io = CoordinatorIO()
        let scheduler = ManualPopoverScheduler()
        let coordinator = makeCoordinator(io: io, scheduler: scheduler)
        let first = try prepareAndShow(coordinator)
        coordinator.endPresentation(first)

        let second = try #require(coordinator.beginPresentation())
        coordinator.endPresentation(first)
        coordinator.markShown(in: first)
        coordinator.contentMayHaveChanged(in: first)
        #expect(!coordinator.prepareForShow(in: first))
        #expect(coordinator.prepareForShow(in: second))
        coordinator.markShown(in: second)
        coordinator.contentMayHaveChanged(in: second)
        #expect(scheduler.work.count == 1)
    }

    @MainActor
    @Test func reentrantSinkSchedulesFreshDrainWithoutLosingIt() throws {
        let io = CoordinatorIO()
        let scheduler = ManualPopoverScheduler()
        let coordinator = makeCoordinator(io: io, scheduler: scheduler)
        let session = try prepareAndShow(coordinator)
        io.measurementSequence = [
            CGSize(width: 320, height: 421),
            CGSize(width: 320, height: 470),
        ]
        var reentered = false
        io.onApply = { _ in
            guard !reentered else { return }
            reentered = true
            coordinator.contentMayHaveChanged(in: session)
        }

        coordinator.contentMayHaveChanged(in: session)
        scheduler.run()
        #expect(scheduler.work.count == 1)
        scheduler.run()
        #expect(io.applications == [
            CGSize(width: 320, height: 421),
            CGSize(width: 320, height: 470),
        ])
    }

    @MainActor
    @Test func preflightSuppressesReentrantMeasurementAndSinkSignals() throws {
        let io = CoordinatorIO()
        let scheduler = ManualPopoverScheduler()
        io.measured = CGSize(width: 320, height: 421)
        io.current = CGSize(width: 320, height: 392)
        let coordinator = makeCoordinator(io: io, scheduler: scheduler)
        let session = try #require(coordinator.beginPresentation())
        io.onMeasure = { coordinator.contentMayHaveChanged(in: session) }
        io.onApply = { _ in coordinator.contentMayHaveChanged(in: session) }

        #expect(coordinator.prepareForShow(in: session))
        #expect(scheduler.work.isEmpty)
        #expect(io.applications == [CGSize(width: 320, height: 421)])
    }

    @MainActor
    @Test func failedPreflightCannotBecomeShown() throws {
        let io = CoordinatorIO()
        let scheduler = ManualPopoverScheduler()
        io.measured = CGSize(width: 320, height: 421)
        io.current = CGSize(width: 320, height: 392)
        io.applyResult = false
        let coordinator = makeCoordinator(io: io, scheduler: scheduler)
        let session = try #require(coordinator.beginPresentation())

        #expect(!coordinator.prepareForShow(in: session))
        coordinator.markShown(in: session)
        coordinator.contentMayHaveChanged(in: session)
        #expect(scheduler.work.isEmpty)
    }

    @MainActor
    @Test func closeAndShutdownFenceQueuedAndLateWork() throws {
        let io = CoordinatorIO()
        let scheduler = ManualPopoverScheduler()
        let coordinator = makeCoordinator(io: io, scheduler: scheduler)
        let session = try prepareAndShow(coordinator)
        io.measured = CGSize(width: 320, height: 470)
        coordinator.contentMayHaveChanged(in: session)
        coordinator.endPresentation(session)
        scheduler.run()
        #expect(io.applications.isEmpty)

        let second = try prepareAndShow(coordinator)
        io.applications.removeAll()
        io.measured = CGSize(width: 320, height: 520)
        coordinator.contentMayHaveChanged(in: second)
        coordinator.shutdown()
        scheduler.run()
        coordinator.contentMayHaveChanged(in: second)
        #expect(coordinator.beginPresentation() == nil)
        #expect(io.applications.isEmpty)
        #expect(scheduler.work.isEmpty)
    }

    @MainActor
    @Test func publicSchedulerAlwaysDefersLiveDrain() async throws {
        let io = CoordinatorIO()
        let coordinator = PopoverSizeCoordinator(
            width: 320,
            measure: { [weak io] in io?.nextMeasurement() },
            readCurrentSize: { [weak io] in io?.readCurrent() },
            applySize: { [weak io] size in io?.apply(size) ?? false }
        )
        let session = try prepareAndShow(coordinator)
        io.measured = CGSize(width: 320, height: 421)

        coordinator.contentMayHaveChanged(in: session)
        #expect(io.applications.isEmpty)

        for _ in 0..<10 where io.applications.isEmpty {
            await Task.yield()
        }
        #expect(io.applications == [CGSize(width: 320, height: 421)])
    }
}
