import Foundation

public struct OAuthRefreshService: AuthRefreshing {
    private struct RefreshResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int64
        let scope: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case scope
        }
    }

    private static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let defaultScopes = ["user:profile", "user:inference", "user:sessions:claude_code", "user:mcp_servers", "user:file_upload"]

    private let tokenProvider: any TokenProvider
    private let session: URLSession

    public init(
        tokenProvider: any TokenProvider = KeychainService(),
        session: URLSession = .shared
    ) {
        self.tokenProvider = tokenProvider
        self.session = session
    }

    public func refreshCredentials(currentSnapshot: OAuthCredentialSnapshot) async -> OAuthRefreshResult {
        guard let refreshToken = currentSnapshot.refreshToken, !refreshToken.isEmpty else {
            return .missingRefreshToken
        }

        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let scope = currentSnapshot.scopes.isEmpty ? Self.defaultScopes.joined(separator: " ") : currentSnapshot.scopes.joined(separator: " ")
        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID,
            "scope": scope,
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            return .unexpectedFailure(error.localizedDescription)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return .networkFailure(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            return .unexpectedFailure(URLError(.badServerResponse).localizedDescription)
        }

        guard httpResponse.statusCode == 200 else {
            if [400, 401, 403].contains(httpResponse.statusCode) {
                return .authRejected(httpResponse.statusCode)
            }
            let bodyString = String(data: data, encoding: .utf8) ?? ""
            return .unexpectedFailure("HTTP \(httpResponse.statusCode): \(String(bodyString.prefix(200)))")
        }

        let payload: RefreshResponse
        do {
            payload = try JSONDecoder().decode(RefreshResponse.self, from: data)
        } catch {
            return .unexpectedFailure(error.localizedDescription)
        }

        let updatedSnapshot = OAuthCredentialSnapshot(
            accessToken: payload.accessToken,
            refreshToken: payload.refreshToken ?? refreshToken,
            expiresAt: Date().millisecondsSince1970 + (payload.expiresIn * 1000),
            scopes: payload.scope?.split(separator: " ").map(String.init) ?? currentSnapshot.scopes,
            subscriptionType: currentSnapshot.subscriptionType,
            rateLimitTier: currentSnapshot.rateLimitTier
        )

        guard tokenProvider.writeOAuthSnapshot(updatedSnapshot) else {
            return .unexpectedFailure("Failed to persist refreshed credentials")
        }

        return .success(newFingerprint: updatedSnapshot.fingerprint)
    }
}

private extension Date {
    var millisecondsSince1970: Int64 {
        Int64((timeIntervalSince1970 * 1000).rounded())
    }
}
