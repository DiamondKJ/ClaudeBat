import Testing
import Foundation
@testable import ClaudeBatCore

@Suite("Network Services", .serialized)
struct NetworkServiceTests {

    @Test func usageAPI_parsesHttpDateRetryAfter() async throws {
        let session = makeStubSession { request in
            #expect(request.value(forHTTPHeaderField: "User-Agent") == "claude-code/2.1.76")
            let retryDate = Date().addingTimeInterval(120)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"

            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 429,
                httpVersion: nil,
                headerFields: ["Retry-After": formatter.string(from: retryDate)]
            )!
            return (response, Data())
        }

        let service = UsageAPIService(session: session)

        do {
            _ = try await service.fetchUsage(token: "tok")
            Issue.record("Expected rate limit error")
        } catch let error as UsageAPIError {
            guard case .rateLimited(let retryAfter) = error else {
                Issue.record("Expected rate limited error, got \(error)")
                return
            }

            #expect(retryAfter != nil)
            #expect((retryAfter ?? 0) > 90)
            #expect((retryAfter ?? 0) <= 120)
        }
    }

    @Test func usageAPI_redactsHTTPBodiesFromErrors() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("top-secret-response".utf8))
        }

        let service = UsageAPIService(session: session)

        do {
            _ = try await service.fetchUsage(token: "tok")
            Issue.record("Expected HTTP error")
        } catch let error as UsageAPIError {
            #expect(error.errorDescription == "HTTP 500")
            guard case .httpError(let statusCode) = error else {
                Issue.record("Expected HTTP error, got \(error)")
                return
            }
            #expect(statusCode == 500)
        }
    }

    @Test func oauthRefresh_omitsScopeWhenSnapshotHasNone() async throws {
        let tokenProvider = MockTokenProvider(
            snapshot: OAuthCredentialSnapshot(accessToken: "old", refreshToken: "refresh-token")
        )
        let session = makeStubSession { request in
            let body = try #require(requestBody(from: request))
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
            #expect(json["scope"] == nil)
            #expect(json["refresh_token"] == "refresh-token")

            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = """
            {"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600}
            """
            return (response, Data(payload.utf8))
        }

        let service = OAuthRefreshService(tokenProvider: tokenProvider, session: session)
        let result = await service.refreshCredentials(
            currentSnapshot: OAuthCredentialSnapshot(accessToken: "old", refreshToken: "refresh-token")
        )

        #expect(result == .success(newFingerprint: OAuthCredentialSnapshot(accessToken: "new-access").fingerprint))
        #expect(tokenProvider.snapshot?.refreshToken == "new-refresh")
    }
}

private func requestBody(from request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }

    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }

    let bufferSize = 1024
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: bufferSize)

    while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: bufferSize)
        guard read > 0 else { break }
        data.append(buffer, count: read)
    }

    return data.isEmpty ? nil : data
}

private func makeStubSession(
    handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
) -> URLSession {
    URLProtocolStub.handler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [URLProtocolStub.self]
    return URLSession(configuration: configuration)
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
