import Foundation

// MARK: - API Response

public struct UsageResponse: Codable {
    public let fiveHour: UsagePeriod
    public let sevenDay: UsagePeriod
    public let sevenDayOpus: UsagePeriod?
    public let sevenDaySonnet: UsagePeriod?
    public let extraUsage: ExtraUsage?
    public let limits: [UsageLimit]?

    public init(fiveHour: UsagePeriod, sevenDay: UsagePeriod, sevenDayOpus: UsagePeriod? = nil, sevenDaySonnet: UsagePeriod? = nil, extraUsage: ExtraUsage? = nil, limits: [UsageLimit]? = nil) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.sevenDayOpus = sevenDayOpus
        self.sevenDaySonnet = sevenDaySonnet
        self.extraUsage = extraUsage
        self.limits = limits
    }

    // API may return additional fields (seven_day_oauth_apps, seven_day_cowork, iguana_necktie, etc.)
    // CodingKeys ensures we only decode what we need and ignore the rest
    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case extraUsage = "extra_usage"
        case limits
    }

    /// Per-model weekly usage rows for the popover breakdown.
    ///
    /// Sourced from the `limits` array (model-scoped weekly entries — "Fable",
    /// "Sonnet", whatever the API names next). Falls back to the legacy
    /// `seven_day_opus`/`seven_day_sonnet` buckets, which the API nulled out
    /// mid-2026 but older cached responses may still carry.
    public var weeklyModelBreakdown: [ModelWeeklyUsage] {
        let scoped = (limits ?? []).enumerated().compactMap { offset, limit -> ModelWeeklyUsage? in
            guard limit.group == "weekly",
                  let name = limit.scope?.model?.displayName,
                  let percent = limit.percent else { return nil }
            return ModelWeeklyUsage(
                id: limit.scope?.model?.id ?? "weekly-\(offset)-\(name)",
                label: name,
                period: UsagePeriod(utilization: percent, resetsAt: limit.resetsAt)
            )
        }
        if !scoped.isEmpty { return scoped }

        var legacy: [ModelWeeklyUsage] = []
        if let opus = sevenDayOpus {
            legacy.append(ModelWeeklyUsage(id: "legacy-opus", label: "Opus", period: opus))
        }
        if let sonnet = sevenDaySonnet {
            legacy.append(ModelWeeklyUsage(id: "legacy-sonnet", label: "Sonnet", period: sonnet))
        }
        return legacy
    }
}

/// One entry in the API's `limits` array. Only `weekly`-group entries with a
/// model scope drive UI today, but all fields decode so future groups
/// (session severity, surface scopes) are available without a schema change.
public struct UsageLimit: Codable {
    public let kind: String?
    public let group: String?
    public let percent: Double?
    public let severity: String?
    public let resetsAt: String?
    public let isActive: Bool?
    public let scope: UsageLimitScope?

    public init(kind: String? = nil, group: String? = nil, percent: Double? = nil, severity: String? = nil, resetsAt: String? = nil, isActive: Bool? = nil, scope: UsageLimitScope? = nil) {
        self.kind = kind
        self.group = group
        self.percent = percent
        self.severity = severity
        self.resetsAt = resetsAt
        self.isActive = isActive
        self.scope = scope
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case group
        case percent
        case severity
        case resetsAt = "resets_at"
        case isActive = "is_active"
        case scope
    }
}

public struct UsageLimitScope: Codable {
    public let model: UsageLimitScopeModel?

    public init(model: UsageLimitScopeModel? = nil) {
        self.model = model
    }
}

public struct UsageLimitScopeModel: Codable {
    public let id: String?
    public let displayName: String?

    public init(id: String? = nil, displayName: String? = nil) {
        self.id = id
        self.displayName = displayName
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

/// A labeled per-model weekly usage row, ready for display.
public struct ModelWeeklyUsage: Identifiable, Equatable {
    public let id: String
    public let label: String
    public let period: UsagePeriod

    public init(id: String, label: String, period: UsagePeriod) {
        self.id = id
        self.label = label
        self.period = period
    }
}

public struct UsagePeriod: Codable, Equatable {
    /// Percentage USED (0-100)
    public let utilization: Double
    public let resetsAt: String?

    public init(utilization: Double, resetsAt: String?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    /// Percentage REMAINING (100 - utilization)
    public var remaining: Double {
        max(0, min(100, 100 - utilization))
    }

    /// Integer remaining for display (no % sign)
    public var remainingInt: Int {
        Int(remaining.rounded())
    }

    /// Parse the ISO 8601 reset time
    public var resetsAtDate: Date? {
        guard let resetsAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: resetsAt) ?? ISO8601DateFormatter().date(from: resetsAt)
    }

    /// Human-readable time until reset
    public var timeUntilReset: String {
        timeUntilReset(reference: Date(), timeZone: .current)
    }

    public func timeUntilReset(reference now: Date, timeZone: TimeZone) -> String {
        guard let date = resetsAtDate else { return "" }
        let interval = date.timeIntervalSince(now)
        guard interval > 0 else { return "Recently reset" }

        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60

        if hours > 24 {
            return "Resets \(Self.formatResetTimestamp(date, reference: now, timeZone: timeZone))"
        } else if hours > 0 {
            return "Resets in \(hours)h \(minutes)m"
        } else {
            return "Resets in \(minutes)m"
        }
    }

    /// Short format for weekly display
    public var resetDateShort: String {
        resetDateShort(reference: Date(), timeZone: .current)
    }

    public func resetDateShort(reference: Date, timeZone: TimeZone) -> String {
        guard let date = resetsAtDate else { return "" }
        return "Resets \(Self.formatResetTimestamp(date, reference: reference, timeZone: timeZone))"
    }

    // MARK: - Reset time formatting (single source of truth)

    // Locale-pinned (en_US_POSIX) so reset times read consistently across every
    // surface and never garble in non-US locales — the retro look is intentionally
    // en-US. All three render sites (SESSION, THIS WEEK, GAME OVER) go through
    // `formatResetTimestamp`, killing the old "2PM" vs "2:30 PM" drift.
    private static let currentDatedResetFormatter = makeResetFormatter(
        dated: true,
        timeZone: .current
    )

    private static let currentTimeResetFormatter = makeResetFormatter(
        dated: false,
        timeZone: .current
    )

    private static func makeResetFormatter(dated: Bool, timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = dated ? "MMM d, h:mm a" : "h:mm a"
        return f
    }

    private static func resetFormatter(dated: Bool, timeZone: TimeZone) -> DateFormatter {
        if timeZone == TimeZone.current {
            return dated ? currentDatedResetFormatter : currentTimeResetFormatter
        }
        return makeResetFormatter(dated: dated, timeZone: timeZone)
    }

    /// Renders an absolute reset time consistently: a dated form for far-off
    /// (weekly) resets, time-only for same-day (session) resets.
    public static func formatResetTimestamp(
        _ date: Date,
        reference: Date = Date(),
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = resetFormatter(
            dated: date.timeIntervalSince(reference) > 24 * 3600,
            timeZone: timeZone
        )
        return formatter.string(from: date)
    }
}

public struct ExtraUsage: Codable {
    public let isEnabled: Bool
    public let monthlyLimit: Int?
    public let usedCredits: Double?
    public let utilization: Double?

    public init(isEnabled: Bool, monthlyLimit: Int? = nil, usedCredits: Double? = nil, utilization: Double? = nil) {
        self.isEnabled = isEnabled
        self.monthlyLimit = monthlyLimit
        self.usedCredits = usedCredits
        self.utilization = utilization
    }

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case utilization
    }

    public var usedFormatted: String {
        guard let used = usedCredits else { return "$0.00" }
        return String(format: "$%.2f", used / 100)
    }

    public var limitFormatted: String {
        guard let limit = monthlyLimit else { return "$0.00" }
        return String(format: "$%.2f", Double(limit) / 100)
    }
}

// MARK: - App State

public enum AppState: Equatable {
    case loading
    case loadingRetro
    case loaded(UsageResponse)
    case noAuth
    case error(String)

    public static func == (lhs: AppState, rhs: AppState) -> Bool {
        switch (lhs, rhs) {
        case (.loading, .loading): return true
        case (.loadingRetro, .loadingRetro): return true
        case (.loaded, .loaded): return true
        case (.noAuth, .noAuth): return true
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}
