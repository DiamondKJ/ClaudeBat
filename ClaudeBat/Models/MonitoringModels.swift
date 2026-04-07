import Foundation
import OSLog

public enum FetchTrigger: String, Codable, Sendable {
    case appLaunch = "app_launch"
    case pollTimer = "poll_timer"
    case popoverOpen = "popover_open"
    case screenWake = "screen_wake"
    case machineWake = "machine_wake"
    case resetBoundary = "reset_boundary"
    case selfHeal = "self_heal"
}

public enum FetchOutcome: String, Codable, Sendable {
    case success = "success"
    case rateLimited = "rate_limited"
    case http401 = "http_401"
    case httpError = "http_error"
    case networkError = "network_error"
    case decodingError = "decoding_error"
    case noToken = "no_token"
    case budgetBlocked = "budget_blocked"
    case serverCooldownBlocked = "server_cooldown_blocked"
    case skippedAlreadyFetching = "skipped_already_fetching"
}

public enum WakeSource: String, Codable, Sendable {
    case screen
    case machine
}

public enum CachedDataReason: String, Codable, Sendable {
    case authInvalid = "auth_invalid"
    case noToken = "no_token"
    case networkError = "network_error"
    case serverError = "server_error"
    case rateLimited = "rate_limited"
}

public enum MonitorEventCategory: String, Codable, Sendable {
    case lifecycle
    case timer
    case fetch
    case auth
    case staleState = "stale_state"
}

public struct MonitorEvent: Codable, Equatable, Sendable {
    public let category: MonitorEventCategory
    public let action: String
    public let trigger: FetchTrigger?
    public let outcome: FetchOutcome?
    public let wakeSource: WakeSource?
    public let message: String?
    public let retryAfterSeconds: Int?

    public init(
        category: MonitorEventCategory,
        action: String,
        trigger: FetchTrigger? = nil,
        outcome: FetchOutcome? = nil,
        wakeSource: WakeSource? = nil,
        message: String? = nil,
        retryAfterSeconds: Int? = nil
    ) {
        self.category = category
        self.action = action
        self.trigger = trigger
        self.outcome = outcome
        self.wakeSource = wakeSource
        self.message = message
        self.retryAfterSeconds = retryAfterSeconds
    }
}

public struct MonitorStatus: Codable, Equatable, Sendable {
    public var pid: Int32
    public var appRunning: Bool
    public var displaySleeping: Bool
    public var lastLaunchAt: Date?
    public var lastAttemptAt: Date?
    public var lastSuccessAt: Date?
    public var lastFailureAt: Date?
    public var lastFailureReason: String?
    public var lastHTTPStatus: Int?
    public var consecutiveFailures: Int
    public var currentPollIntervalSeconds: Int
    public var usingCachedData: Bool
    public var cacheAgeSeconds: Int?
    public var sessionResetsAt: Date?
    public var sessionRemaining: Int?
    public var lastWakeAt: Date?
    public var lastWakeSource: WakeSource?
    public var buildFlavor: String
    public var gitCommit: String
    public var staleReason: CachedDataReason?

    public init(
        pid: Int32 = ProcessInfo.processInfo.processIdentifier,
        appRunning: Bool = false,
        displaySleeping: Bool = false,
        lastLaunchAt: Date? = nil,
        lastAttemptAt: Date? = nil,
        lastSuccessAt: Date? = nil,
        lastFailureAt: Date? = nil,
        lastFailureReason: String? = nil,
        lastHTTPStatus: Int? = nil,
        consecutiveFailures: Int = 0,
        currentPollIntervalSeconds: Int = 0,
        usingCachedData: Bool = false,
        cacheAgeSeconds: Int? = nil,
        sessionResetsAt: Date? = nil,
        sessionRemaining: Int? = nil,
        lastWakeAt: Date? = nil,
        lastWakeSource: WakeSource? = nil,
        buildFlavor: String = "standard",
        gitCommit: String = "unknown",
        staleReason: CachedDataReason? = nil
    ) {
        self.pid = pid
        self.appRunning = appRunning
        self.displaySleeping = displaySleeping
        self.lastLaunchAt = lastLaunchAt
        self.lastAttemptAt = lastAttemptAt
        self.lastSuccessAt = lastSuccessAt
        self.lastFailureAt = lastFailureAt
        self.lastFailureReason = lastFailureReason
        self.lastHTTPStatus = lastHTTPStatus
        self.consecutiveFailures = consecutiveFailures
        self.currentPollIntervalSeconds = currentPollIntervalSeconds
        self.usingCachedData = usingCachedData
        self.cacheAgeSeconds = cacheAgeSeconds
        self.sessionResetsAt = sessionResetsAt
        self.sessionRemaining = sessionRemaining
        self.lastWakeAt = lastWakeAt
        self.lastWakeSource = lastWakeSource
        self.buildFlavor = buildFlavor
        self.gitCommit = gitCommit
        self.staleReason = staleReason
    }

    enum CodingKeys: String, CodingKey {
        case pid
        case appRunning = "app_running"
        case displaySleeping = "display_sleeping"
        case lastLaunchAt = "last_launch_at"
        case lastAttemptAt = "last_attempt_at"
        case lastSuccessAt = "last_success_at"
        case lastFailureAt = "last_failure_at"
        case lastFailureReason = "last_failure_reason"
        case lastHTTPStatus = "last_http_status"
        case consecutiveFailures = "consecutive_failures"
        case currentPollIntervalSeconds = "current_poll_interval_seconds"
        case usingCachedData = "using_cached_data"
        case cacheAgeSeconds = "cache_age_seconds"
        case sessionResetsAt = "session_resets_at"
        case sessionRemaining = "session_remaining"
        case lastWakeAt = "last_wake_at"
        case lastWakeSource = "last_wake_source"
        case buildFlavor = "build_flavor"
        case gitCommit = "git_commit"
        case staleReason = "stale_reason"
    }
}

public struct MonitorEventRecord: Codable, Sendable {
    public let timestamp: Date
    public let pid: Int32
    public let appVersion: String
    public let bundleIdentifier: String
    public let buildFlavor: String
    public let gitCommit: String
    public let eventCategory: String
    public let action: String
    public let trigger: String?
    public let outcome: String?
    public let wakeSource: String?
    public let message: String?
    public let retryAfterSeconds: Int?
    public let appRunning: Bool
    public let statusPID: Int32
    public let displaySleeping: Bool
    public let lastLaunchAt: Date?
    public let lastAttemptAt: Date?
    public let lastSuccessAt: Date?
    public let lastFailureAt: Date?
    public let lastFailureReason: String?
    public let lastHTTPStatus: Int?
    public let consecutiveFailures: Int
    public let currentPollIntervalSeconds: Int
    public let usingCachedData: Bool
    public let cacheAgeSeconds: Int?
    public let sessionResetsAt: Date?
    public let sessionRemaining: Int?
    public let lastWakeAt: Date?
    public let lastWakeSource: String?
    public let staleReason: String?

    public init(event: MonitorEvent, status: MonitorStatus, buildInfo: AppBuildInfo, timestamp: Date = Date()) {
        self.timestamp = timestamp
        self.pid = ProcessInfo.processInfo.processIdentifier
        self.appVersion = buildInfo.appVersion
        self.bundleIdentifier = buildInfo.bundleIdentifier
        self.buildFlavor = buildInfo.buildFlavor
        self.gitCommit = buildInfo.gitCommit
        self.eventCategory = event.category.rawValue
        self.action = event.action
        self.trigger = event.trigger?.rawValue
        self.outcome = event.outcome?.rawValue
        self.wakeSource = event.wakeSource?.rawValue
        self.message = event.message
        self.retryAfterSeconds = event.retryAfterSeconds
        self.appRunning = status.appRunning
        self.statusPID = status.pid
        self.displaySleeping = status.displaySleeping
        self.lastLaunchAt = status.lastLaunchAt
        self.lastAttemptAt = status.lastAttemptAt
        self.lastSuccessAt = status.lastSuccessAt
        self.lastFailureAt = status.lastFailureAt
        self.lastFailureReason = status.lastFailureReason
        self.lastHTTPStatus = status.lastHTTPStatus
        self.consecutiveFailures = status.consecutiveFailures
        self.currentPollIntervalSeconds = status.currentPollIntervalSeconds
        self.usingCachedData = status.usingCachedData
        self.cacheAgeSeconds = status.cacheAgeSeconds
        self.sessionResetsAt = status.sessionResetsAt
        self.sessionRemaining = status.sessionRemaining
        self.lastWakeAt = status.lastWakeAt
        self.lastWakeSource = status.lastWakeSource?.rawValue
        self.staleReason = status.staleReason?.rawValue
    }

    public var logLevel: OSLogType {
        switch outcome {
        case FetchOutcome.success.rawValue:
            return .info
        case FetchOutcome.rateLimited.rawValue,
             FetchOutcome.budgetBlocked.rawValue,
             FetchOutcome.serverCooldownBlocked.rawValue,
             FetchOutcome.skippedAlreadyFetching.rawValue:
            return .default
        case nil:
            return .info
        default:
            return .error
        }
    }

    public var summary: String {
        let fields: [String] = [
            "event=\(eventCategory)",
            "action=\(action)",
            "trigger=\(trigger ?? "-")",
            "outcome=\(outcome ?? "-")",
            "wake=\(wakeSource ?? "-")",
            "cached=\(usingCachedData)",
            "cache_age=\(cacheAgeSeconds.map(String.init) ?? "-")",
            "status=\(lastHTTPStatus.map(String.init) ?? "-")",
            "failures=\(consecutiveFailures)",
            "poll=\(currentPollIntervalSeconds)",
            "message=\(message ?? "-")",
        ]
        return fields.joined(separator: " ")
    }

    enum CodingKeys: String, CodingKey {
        case timestamp
        case pid
        case appVersion = "app_version"
        case bundleIdentifier = "bundle_identifier"
        case buildFlavor = "build_flavor"
        case gitCommit = "git_commit"
        case eventCategory = "event_category"
        case action
        case trigger
        case outcome
        case wakeSource = "wake_source"
        case message
        case retryAfterSeconds = "retry_after_seconds"
        case appRunning = "app_running"
        case statusPID = "status_pid"
        case displaySleeping = "display_sleeping"
        case lastLaunchAt = "last_launch_at"
        case lastAttemptAt = "last_attempt_at"
        case lastSuccessAt = "last_success_at"
        case lastFailureAt = "last_failure_at"
        case lastFailureReason = "last_failure_reason"
        case lastHTTPStatus = "last_http_status"
        case consecutiveFailures = "consecutive_failures"
        case currentPollIntervalSeconds = "current_poll_interval_seconds"
        case usingCachedData = "using_cached_data"
        case cacheAgeSeconds = "cache_age_seconds"
        case sessionResetsAt = "session_resets_at"
        case sessionRemaining = "session_remaining"
        case lastWakeAt = "last_wake_at"
        case lastWakeSource = "last_wake_source"
        case staleReason = "stale_reason"
    }
}
