import Foundation

// MARK: - API Response

public struct UsageResponse: Codable {
    public let fiveHour: UsagePeriod
    public let sevenDay: UsagePeriod
    public let sevenDayOpus: UsagePeriod?
    public let sevenDaySonnet: UsagePeriod?
    public let extraUsage: ExtraUsage?

    public init(fiveHour: UsagePeriod, sevenDay: UsagePeriod, sevenDayOpus: UsagePeriod? = nil, sevenDaySonnet: UsagePeriod? = nil, extraUsage: ExtraUsage? = nil) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.sevenDayOpus = sevenDayOpus
        self.sevenDaySonnet = sevenDaySonnet
        self.extraUsage = extraUsage
    }

    // API may return additional fields (seven_day_oauth_apps, seven_day_cowork, iguana_necktie, etc.)
    // CodingKeys ensures we only decode what we need and ignore the rest
    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case extraUsage = "extra_usage"
    }
}

public struct UsagePeriod: Codable {
    /// Percentage USED (0-100)
    public let utilization: Double
    public let resetsAt: String

    public init(utilization: Double, resetsAt: String) {
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
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: resetsAt) ?? ISO8601DateFormatter().date(from: resetsAt)
    }

    /// Human-readable time until reset
    public var timeUntilReset: String {
        guard let date = resetsAtDate else { return "" }
        let now = Date()
        let interval = date.timeIntervalSince(now)
        guard interval > 0 else { return "Recently reset" }

        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60

        if hours > 24 {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, ha"
            return "Resets \(formatter.string(from: date))"
        } else if hours > 0 {
            return "Resets in \(hours)h \(minutes)m"
        } else {
            return "Resets in \(minutes)m"
        }
    }

    /// Short format for weekly display
    public var resetDateShort: String {
        guard let date = resetsAtDate else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, ha"
        return "Resets \(formatter.string(from: date))"
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
