import Foundation
import SwiftUI
import AppKit

@Observable
public final class UsageViewModel {
    // MARK: - Published State

    public var usage: UsageResponse?
    public var freshness: Freshness = .empty
    public var fetchedAt: Date?
    public var errorMessage: String?
    public var popoverIsOpen = false {
        didSet { restartPolling() }
    }
    public var batExpression: BatExpression = .default

    public enum Freshness {
        case empty
        case fresh
        case stale
        case refreshing
    }

    // MARK: - Private

    private let tokenProvider: any TokenProvider
    private let api: any UsageFetching
    private let budget: any BudgetTracking
    private var cache: any UsageCaching
    private var pollingTimer: Timer?
    private var isFetching = false
    private var consecutiveFailures = 0
    private var sleepObserver: Any?
    private var screenWakeObserver: Any?
    private var machineWakeObserver: Any?

    private static let basePollOpen: TimeInterval = 75
    private static let basePollClosed: TimeInterval = 120
    private static let maxBackoff: TimeInterval = 1800

    private var pollInterval: TimeInterval {
        let base = popoverIsOpen ? Self.basePollOpen : Self.basePollClosed
        if consecutiveFailures == 0 { return base }
        let backoff = base * pow(2.0, Double(consecutiveFailures - 1))
        return min(backoff, Self.maxBackoff)
    }

    // MARK: - Init

    public init(
        tokenProvider: any TokenProvider = KeychainService(),
        api: any UsageFetching = UsageAPIService(),
        budget: any BudgetTracking = SlidingWindowBudget(),
        cache: any UsageCaching = UsageCache(),
        startImmediately: Bool = true
    ) {
        self.tokenProvider = tokenProvider
        self.api = api
        self.budget = budget
        self.cache = cache

        if let cached = cache.read() {
            usage = cached.value
            fetchedAt = cached.fetchedAt
            freshness = cached.age > 60 ? .stale : .fresh
        }

        if startImmediately {
            observeSleepWake()
            startPolling()

            Task { @MainActor in
                await fetchIfBudgetAllows()
            }
        }
    }

    deinit {
        pollingTimer?.invalidate()
        if let obs = sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(obs) }
        if let obs = screenWakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(obs) }
        if let obs = machineWakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(obs) }
    }

    // MARK: - Public Actions

    public func onPopoverOpen() {
        popoverIsOpen = true
        let needsFetch: Bool
        if hasResetBoundaryPassed {
            needsFetch = true
        } else if let age = fetchedAt.map({ Date().timeIntervalSince($0) }), age > 60 {
            needsFetch = true
        } else {
            needsFetch = false
        }
        if needsFetch {
            Task { @MainActor in
                await fetchIfBudgetAllows()
            }
        }
    }

    public func onPopoverClose() {
        popoverIsOpen = false
    }

    // MARK: - Fetch Logic

    @MainActor
    func fetchIfBudgetAllows() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

        let canGo = await budget.canRequest()
        if !canGo {
            // Reset boundary can bypass local budget, but never the server cooldown
            if hasResetBoundaryPassed {
                let serverBlocked = await budget.isServerCooldownActive()
                if serverBlocked { return }
            } else {
                return
            }
        }

        guard let token = tokenProvider.readToken() else {
            if usage == nil {
                freshness = .empty
                errorMessage = nil // Will show NoAuth, not Error
            } else {
                freshness = .stale
            }
            return
        }

        if usage != nil {
            freshness = .refreshing
            startBatWink()
        } else {
            freshness = .empty
        }

        await budget.recordRequest()

        do {
            let response = try await api.fetchUsage(token: token)
            cache.write(response)
            usage = response
            fetchedAt = Date()
            freshness = .fresh
            errorMessage = nil
            consecutiveFailures = 0
            restartPolling()
            stopBatWink()
        } catch let error as UsageAPIError {
            stopBatWink()
            switch error {
            case .rateLimited(let retryAfter):
                let delay = (retryAfter ?? 300) < 1 ? 300 : retryAfter!
                await budget.setRetryAfter(seconds: delay)
                if usage != nil {
                    freshness = fetchedAt.map { Date().timeIntervalSince($0) > 60 } == true ? .stale : .fresh
                }
                // Don't count rate limit as a failure for backoff
            case .noToken:
                if usage == nil { freshness = .empty }
            default:
                consecutiveFailures += 1
                restartPolling()
                if usage == nil {
                    errorMessage = error.localizedDescription
                } else {
                    freshness = .stale
                }
            }
        } catch {
            stopBatWink()
            consecutiveFailures += 1
            restartPolling()
            if usage == nil {
                errorMessage = error.localizedDescription
            } else {
                freshness = .stale
            }
        }
    }

    // MARK: - Polling

    private func startPolling() {
        restartPolling()
    }

    private func restartPolling() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.fetchIfBudgetAllows()
            }
        }
    }

    // MARK: - Sleep/Wake

    private func observeSleepWake() {
        let nc = NSWorkspace.shared.notificationCenter

        sleepObserver = nc.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.pollingTimer?.invalidate()
        }

        screenWakeObserver = nc.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleWake()
        }

        machineWakeObserver = nc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleWake()
        }
    }

    private func handleWake() {
        restartPolling()
        let dataAge = fetchedAt.map { Date().timeIntervalSince($0) } ?? .infinity
        if dataAge > 300 {
            // Data is >5 min old — bypass local budget, respect server cooldown
            Task { @MainActor in
                let serverBlocked = await self.budget.isServerCooldownActive()
                guard !serverBlocked else { return }
                await self.fetchIfBudgetAllows()
            }
        } else {
            Task { @MainActor in
                await self.fetchIfBudgetAllows()
            }
        }
    }

    // MARK: - Bat Wink Animation

    private var winkTimer: Timer?

    private func startBatWink() {
        let expressions: [BatExpression] = [.winking, .default]
        var index = 0
        batExpression = .winking
        winkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            index = (index + 1) % expressions.count
            self?.batExpression = expressions[index]
        }
    }

    private func stopBatWink() {
        winkTimer?.invalidate()
        winkTimer = nil
        batExpression = .default
    }

    // MARK: - Computed

    public var sessionRemaining: Int {
        usage?.fiveHour.remainingInt ?? 0
    }

    public var isFullyMaxed: Bool {
        guard let u = usage else { return false }
        return u.fiveHour.remaining <= 0 && u.sevenDay.remaining <= 0
    }

    public var hasNoAuth: Bool {
        tokenProvider.readToken() == nil
    }

    public var hasError: Bool {
        usage == nil && errorMessage != nil
    }

    private var hasResetBoundaryPassed: Bool {
        guard let resetsAt = usage?.fiveHour.resetsAtDate else { return false }
        return Date() > resetsAt
    }
}
