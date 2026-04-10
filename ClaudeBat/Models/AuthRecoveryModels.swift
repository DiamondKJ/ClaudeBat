import Foundation
import CryptoKit

public struct OAuthCredentialSnapshot: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Int64?
    public let scopes: [String]
    public let subscriptionType: String?
    public let rateLimitTier: String?

    public init(
        accessToken: String,
        refreshToken: String? = nil,
        expiresAt: Int64? = nil,
        scopes: [String] = [],
        subscriptionType: String? = nil,
        rateLimitTier: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scopes = scopes
        self.subscriptionType = subscriptionType
        self.rateLimitTier = rateLimitTier
    }

    public var fingerprint: String {
        Self.fingerprint(for: accessToken)
    }

    public var expiresAtDate: Date? {
        guard let expiresAt else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(expiresAt) / 1000)
    }

    public static func fingerprint(for token: String) -> String {
        let digest = SHA256.hash(data: Data(token.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

public enum SessionClassifierDecision: String, Codable, Equatable, Sendable {
    case fetchUsageNormally = "fetch_usage_normally"
    case refreshAuthThenFetch = "refresh_auth_then_fetch"
    case showReconnect = "show_reconnect"
    case showOffline = "show_offline"
    case showRecoveringAndRetryLater = "show_recovering_and_retry_later"
}

public enum AuthRecoveryMethod: String, Codable, Equatable, Sendable {
    case native
    case claudeCLI = "claude_cli"
}

public enum AuthRecoveryPhase: String, Codable, Equatable, Sendable {
    case idle
    case nativeRefreshInFlight = "native_refresh_in_flight"
    case claudeCLIRecoveryInFlight = "claude_cli_recovery_in_flight"
    case awaitingUsageValidation = "awaiting_usage_validation"
    case failedRequiresReconnect = "failed_requires_reconnect"
}

public enum AuthRecoveryResult: String, Codable, Equatable, Sendable {
    case success
    case missingCredentials = "missing_credentials"
    case offline
    case authRejected = "auth_rejected"
    case timedOut = "timed_out"
    case unexpectedFailure = "unexpected_failure"
}

public enum OAuthRefreshResult: Equatable, Sendable {
    case success(newFingerprint: String)
    case missingRefreshToken
    case networkFailure(String)
    case authRejected(Int?)
    case unexpectedFailure(String)
}

public enum ClaudeCLIRecoveryResult: Equatable, Sendable {
    case success
    case timedOut
    case launchFailed(String)
}

public struct RecoverySnapshot: Codable, Equatable, Sendable {
    public var lastSuccessfulUsageAt: Date?
    public var lastSuccessfulUsageSessionResetAt: Date?
    public var lastSuccessfulAuthRefreshAt: Date?
    public var lastSuccessfulAuthRefreshMethod: AuthRecoveryMethod?
    public var lastTokenFingerprint: String?
    public var lastTokenFingerprintChangedAt: Date?
    public var lastRecoveryAttemptAt: Date?
    public var lastRecoveryResult: AuthRecoveryResult?
    public var lastHiddenClaudeActivationAt: Date?
    public var authRecoveryPhase: AuthRecoveryPhase?

    public init(
        lastSuccessfulUsageAt: Date? = nil,
        lastSuccessfulUsageSessionResetAt: Date? = nil,
        lastSuccessfulAuthRefreshAt: Date? = nil,
        lastSuccessfulAuthRefreshMethod: AuthRecoveryMethod? = nil,
        lastTokenFingerprint: String? = nil,
        lastTokenFingerprintChangedAt: Date? = nil,
        lastRecoveryAttemptAt: Date? = nil,
        lastRecoveryResult: AuthRecoveryResult? = nil,
        lastHiddenClaudeActivationAt: Date? = nil,
        authRecoveryPhase: AuthRecoveryPhase? = nil
    ) {
        self.lastSuccessfulUsageAt = lastSuccessfulUsageAt
        self.lastSuccessfulUsageSessionResetAt = lastSuccessfulUsageSessionResetAt
        self.lastSuccessfulAuthRefreshAt = lastSuccessfulAuthRefreshAt
        self.lastSuccessfulAuthRefreshMethod = lastSuccessfulAuthRefreshMethod
        self.lastTokenFingerprint = lastTokenFingerprint
        self.lastTokenFingerprintChangedAt = lastTokenFingerprintChangedAt
        self.lastRecoveryAttemptAt = lastRecoveryAttemptAt
        self.lastRecoveryResult = lastRecoveryResult
        self.lastHiddenClaudeActivationAt = lastHiddenClaudeActivationAt
        self.authRecoveryPhase = authRecoveryPhase
    }
}
