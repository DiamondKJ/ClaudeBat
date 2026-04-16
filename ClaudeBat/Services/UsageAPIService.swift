import Foundation

public enum UsageAPIError: Error, LocalizedError {
    case noToken
    case networkError(Error)
    case rateLimited(retryAfter: TimeInterval?)
    case httpError(Int)
    case decodingError

    public var errorDescription: String? {
        switch self {
        case .noToken: return "No auth token found"
        case .networkError: return "Network error"
        case .rateLimited: return "Rate limited"
        case .httpError(let code): return "HTTP \(code)"
        case .decodingError: return "Unexpected API response"
        }
    }
}

public struct UsageAPIService: UsageFetching {
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchUsage(token: String) async throws -> UsageResponse {
        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("claude-code/2.1.76", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UsageAPIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UsageAPIError.networkError(URLError(.badServerResponse))
        }

        if httpResponse.statusCode == 429 {
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap(Self.parseRetryAfter)
            throw UsageAPIError.rateLimited(retryAfter: retryAfter)
        }

        guard httpResponse.statusCode == 200 else {
            throw UsageAPIError.httpError(httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(UsageResponse.self, from: data)
        } catch {
            throw UsageAPIError.decodingError
        }
    }

    private static func parseRetryAfter(_ value: String) -> TimeInterval? {
        if let seconds = TimeInterval(value) {
            return seconds
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"

        guard let retryDate = formatter.date(from: value) else { return nil }
        return max(0, retryDate.timeIntervalSinceNow)
    }
}
