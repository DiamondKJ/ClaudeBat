import Foundation

public enum UsageAPIError: Error, LocalizedError {
    case noToken
    case networkError(Error)
    case rateLimited(retryAfter: TimeInterval?)
    case httpError(Int, String)
    case decodingError(Error, String)

    public var errorDescription: String? {
        switch self {
        case .noToken: return "No auth token found"
        case .networkError(let e): return "Network error: \(e.localizedDescription)"
        case .rateLimited: return "Rate limited"
        case .httpError(let code, let body): return "HTTP \(code): \(body)"
        case .decodingError(let e, _): return "Decode error: \(e.localizedDescription)"
        }
    }
}

public struct UsageAPIService: UsageFetching {
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    public init() {}

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
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw UsageAPIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UsageAPIError.networkError(URLError(.badServerResponse))
        }

        if httpResponse.statusCode == 429 {
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap { TimeInterval($0) }
            throw UsageAPIError.rateLimited(retryAfter: retryAfter)
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw UsageAPIError.httpError(httpResponse.statusCode, String(body.prefix(200)))
        }

        do {
            return try JSONDecoder().decode(UsageResponse.self, from: data)
        } catch {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw UsageAPIError.decodingError(error, String(body.prefix(500)))
        }
    }
}
