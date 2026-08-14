import CoreGraphics
import Foundation

/// Owns usage-popover sizing transactions without retaining a previous
/// content height.
@MainActor
public final class PopoverSizeCoordinator {
    public struct Session: Hashable, Sendable {
        fileprivate let rawValue: UInt64
    }

    public typealias Measurer = @MainActor @Sendable () -> CGSize?
    public typealias CurrentSizeReader = @MainActor @Sendable () -> CGSize?
    public typealias SizeSink = @MainActor @Sendable (CGSize) -> Bool

    typealias ScheduledWork = @MainActor @Sendable () -> Void
    typealias Scheduler = @MainActor @Sendable (@escaping ScheduledWork) -> Void

    struct DebugCounters: Equatable {
        var scheduledDrains = 0
        var drains = 0
        var measurements = 0
        var currentSizeReads = 0
        var sinkCalls = 0
        var maxPendingTargets = 0
    }

    private enum Phase: Equatable {
        case inactive
        case opening(Session, prepared: Bool)
        case preparing(Session)
        case shown(Session)
        case terminal
    }

    private struct DrainToken: Equatable, Sendable {
        let session: Session
        let serial: UInt64
    }

    private let width: CGFloat
    private let measure: Measurer
    private let readCurrentSize: CurrentSizeReader
    private let applySize: SizeSink
    private let scheduler: Scheduler

    private var phase: Phase = .inactive
    private var nextSessionRawValue: UInt64 = 0
    private var nextDrainSerial: UInt64 = 0
    private var pendingDrain: DrainToken?
    private(set) var debugCounters = DebugCounters()

    public init(
        width: CGFloat,
        measure: @escaping Measurer,
        readCurrentSize: @escaping CurrentSizeReader,
        applySize: @escaping SizeSink
    ) {
        self.width = width
        self.measure = measure
        self.readCurrentSize = readCurrentSize
        self.applySize = applySize
        self.scheduler = { work in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    work()
                }
            }
        }
    }

    init(
        width: CGFloat,
        measure: @escaping Measurer,
        readCurrentSize: @escaping CurrentSizeReader,
        applySize: @escaping SizeSink,
        scheduler: @escaping Scheduler
    ) {
        self.width = width
        self.measure = measure
        self.readCurrentSize = readCurrentSize
        self.applySize = applySize
        self.scheduler = scheduler
    }

    public func beginPresentation() -> Session? {
        guard phase != .terminal else { return nil }
        invalidatePendingDrain()
        nextSessionRawValue &+= 1
        let session = Session(rawValue: nextSessionRawValue)
        phase = .opening(session, prepared: false)
        return session
    }

    @discardableResult
    public func prepareForShow(in session: Session) -> Bool {
        guard case .opening(let currentSession, _) = phase, currentSession == session else {
            return false
        }

        invalidatePendingDrain()
        phase = .preparing(session)
        debugCounters.measurements += 1
        guard let measured = normalizedTarget(from: measure()) else {
            restoreUnpreparedOpeningIfCurrent(session)
            return false
        }

        guard case .preparing(session) = phase else { return false }
        debugCounters.currentSizeReads += 1
        let current = readCurrentSize()
        let applied: Bool
        if sizesMatch(current: current, target: measured) {
            applied = true
        } else {
            debugCounters.sinkCalls += 1
            applied = applySize(measured)
        }

        guard case .preparing(session) = phase else { return false }
        guard applied else {
            phase = .opening(session, prepared: false)
            return false
        }

        invalidatePendingDrain()
        phase = .opening(session, prepared: true)
        return true
    }

    public func markShown(in session: Session) {
        guard case .opening(let current, prepared: true) = phase,
              current == session else { return }
        phase = .shown(session)
    }

    public func contentMayHaveChanged(in session: Session) {
        guard case .shown(let current) = phase, current == session else { return }
        guard pendingDrain == nil else { return }

        nextDrainSerial &+= 1
        let token = DrainToken(session: session, serial: nextDrainSerial)
        pendingDrain = token
        debugCounters.scheduledDrains += 1
        debugCounters.maxPendingTargets = max(debugCounters.maxPendingTargets, 1)

        scheduler { [weak self] in
            self?.drain(token)
        }
    }

    public func endPresentation(_ session: Session) {
        switch phase {
        case .opening(let current, _), .preparing(let current), .shown(let current):
            guard current == session else { return }
            invalidatePendingDrain()
            phase = .inactive
        case .inactive, .terminal:
            return
        }
    }

    public func shutdown() {
        guard phase != .terminal else { return }
        invalidatePendingDrain()
        phase = .terminal
    }

    private func drain(_ token: DrainToken) {
        guard case .shown(let current) = phase,
              current == token.session,
              pendingDrain == token else { return }

        // Remove only this task's slot before calling any injected code. A
        // reentrant invalidation can now schedule its own independent drain.
        pendingDrain = nil
        debugCounters.drains += 1
        debugCounters.measurements += 1
        guard let target = normalizedTarget(from: measure()) else { return }
        guard case .shown(let afterMeasure) = phase, afterMeasure == token.session else { return }

        debugCounters.currentSizeReads += 1
        let currentSize = readCurrentSize()
        guard case .shown(let afterRead) = phase, afterRead == token.session else { return }
        guard !sizesMatch(current: currentSize, target: target) else { return }

        debugCounters.sinkCalls += 1
        _ = applySize(target)
        // Never mutate coordinator state after the sink returns. The sink may
        // synchronously end a session or enqueue a new drain.
    }

    private func invalidatePendingDrain() {
        pendingDrain = nil
    }

    private func restoreUnpreparedOpeningIfCurrent(_ session: Session) {
        guard case .preparing(session) = phase else { return }
        phase = .opening(session, prepared: false)
    }

    private func normalizedTarget(from measured: CGSize?) -> CGSize? {
        guard width.isFinite, width > 0,
              let measured,
              measured.width.isFinite,
              measured.height.isFinite,
              measured.width > 0,
              measured.height > 0,
              let height = Self.normalizedHeight(measured.height) else { return nil }
        return CGSize(width: width, height: height)
    }

    private func sizesMatch(current: CGSize?, target: CGSize) -> Bool {
        guard let current,
              current.width.isFinite,
              current.width == width,
              let currentHeight = Self.normalizedHeight(current.height) else { return false }
        return currentHeight == target.height
    }

    static func normalizedHeight(_ height: CGFloat) -> CGFloat? {
        guard height.isFinite, height > 0 else { return nil }
        let doubled = height * 2
        guard doubled.isFinite else { return nil }
        let normalized = doubled.rounded(.toNearestOrAwayFromZero) / 2
        guard normalized.isFinite, normalized > 0 else { return nil }
        return normalized
    }
}
