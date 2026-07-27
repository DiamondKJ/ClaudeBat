import Testing
import Foundation
@testable import ClaudeBatCore

@Suite("CredentialBlobCodec")
struct CredentialBlobCodecTests {

    // MARK: - Parsing

    @Test func parsesScopesAsArray() throws {
        let json: [String: Any] = [
            "claudeAiOauth": [
                "accessToken": "tok",
                "scopes": ["user:inference", "user:profile"],
            ],
        ]

        let snapshot = try #require(CredentialBlobCodec.snapshot(fromJSONObject: json))
        #expect(snapshot.scopes == ["user:inference", "user:profile"])
    }

    @Test func parsesScopesAsSpaceDelimitedString() throws {
        let json: [String: Any] = [
            "claudeAiOauth": [
                "accessToken": "tok",
                "scopes": "user:inference user:profile",
            ],
        ]

        let snapshot = try #require(CredentialBlobCodec.snapshot(fromJSONObject: json))
        #expect(snapshot.scopes == ["user:inference", "user:profile"])
    }

    @Test func parsesExpiresAtAsNumber() throws {
        let json: [String: Any] = [
            "claudeAiOauth": ["accessToken": "tok", "expiresAt": 1785163669642],
        ]

        let snapshot = try #require(CredentialBlobCodec.snapshot(fromJSONObject: json))
        #expect(snapshot.expiresAt == 1_785_163_669_642)
    }

    @Test func parsesExpiresAtAsString() throws {
        let json: [String: Any] = [
            "claudeAiOauth": ["accessToken": "tok", "expiresAt": "1785163669642"],
        ]

        let snapshot = try #require(CredentialBlobCodec.snapshot(fromJSONObject: json))
        #expect(snapshot.expiresAt == 1_785_163_669_642)
    }

    @Test func parsesFullBlob() throws {
        let snapshot = try #require(
            CredentialBlobCodec.snapshot(fromJSONObject: Self.realisticBlob())
        )

        #expect(snapshot.accessToken == "access-abc")
        #expect(snapshot.refreshToken == "refresh-xyz")
        #expect(snapshot.expiresAt == 1_785_163_669_642)
        #expect(snapshot.scopes == ["user:inference", "user:profile"])
        #expect(snapshot.subscriptionType == "max")
        #expect(snapshot.rateLimitTier == "default_claude_max_20x")
    }

    @Test func fallsBackToAccessTokenKey() throws {
        let snapshot = try #require(
            CredentialBlobCodec.snapshot(fromJSONObject: ["access_token": "bare"])
        )
        #expect(snapshot.accessToken == "bare")
        #expect(snapshot.refreshToken == nil)
    }

    @Test func returnsNilWhenBlobHasNoRecognizedToken() {
        #expect(CredentialBlobCodec.snapshot(fromJSONObject: ["somethingElse": 1]) == nil)
    }

    @Test func returnsNilWhenOAuthSectionLacksAccessToken() {
        let json: [String: Any] = ["claudeAiOauth": ["refreshToken": "only-refresh"]]
        #expect(CredentialBlobCodec.snapshot(fromJSONObject: json) == nil)
    }

    @Test func treatsNonJSONRawStringAsBareToken() throws {
        let snapshot = try #require(CredentialBlobCodec.snapshot(fromRawString: "  sk-raw-token\n"))
        #expect(snapshot.accessToken == "sk-raw-token")
    }

    @Test func returnsNilForEmptyRawString() {
        #expect(CredentialBlobCodec.snapshot(fromRawString: "   \n") == nil)
    }

    @Test func parsesRawJSONString() throws {
        let data = try JSONSerialization.data(withJSONObject: Self.realisticBlob())
        let raw = try #require(String(data: data, encoding: .utf8))

        let snapshot = try #require(CredentialBlobCodec.snapshot(fromRawString: raw))
        #expect(snapshot.accessToken == "access-abc")
    }

    // MARK: - Merge invariants
    //
    // These are the tests that stand between this app and wiping the user's
    // Claude Code login plus every MCP server credential they have.

    @Test func mergePreservesUnknownTopLevelKeys() throws {
        let original = Self.realisticBlob()
        let merged = CredentialBlobCodec.merged(
            OAuthCredentialSnapshot(accessToken: "new-access"),
            into: original
        )

        let mcp = try #require(merged["mcpOAuth"] as? [String: Any])
        let server = try #require(mcp["linear-server|638130d5ab3558f4"] as? [String: Any])
        #expect(server["clientSecret"] as? String == "mcp-client-secret")
        #expect(server["serverUrl"] as? String == "https://mcp.linear.app")

        let discovery = try #require(server["discoveryState"] as? [String: Any])
        #expect(discovery["oauthMetadataFound"] as? Bool == true)
    }

    @Test func mergePreservesUnknownOAuthFields() throws {
        let merged = CredentialBlobCodec.merged(
            OAuthCredentialSnapshot(accessToken: "new-access"),
            into: Self.realisticBlob()
        )

        let oauth = try #require(merged["claudeAiOauth"] as? [String: Any])
        #expect(oauth["refreshTokenExpiresAt"] as? Int == 1_787_556_898_642)
    }

    @Test func mergeDoesNotDeleteFieldsAbsentFromSnapshot() throws {
        // A partial snapshot — nil refreshToken/subscriptionType/rateLimitTier and
        // empty scopes — must leave the existing values alone rather than deleting
        // the keys.
        let merged = CredentialBlobCodec.merged(
            OAuthCredentialSnapshot(accessToken: "new-access"),
            into: Self.realisticBlob()
        )

        let oauth = try #require(merged["claudeAiOauth"] as? [String: Any])
        #expect(oauth["accessToken"] as? String == "new-access")
        #expect(oauth["refreshToken"] as? String == "refresh-xyz")
        #expect(oauth["subscriptionType"] as? String == "max")
        #expect(oauth["rateLimitTier"] as? String == "default_claude_max_20x")
        #expect(oauth["scopes"] as? [String] == ["user:inference", "user:profile"])
        #expect(oauth["expiresAt"] as? Int == 1_785_163_669_642)
    }

    @Test func mergeOverwritesFieldsPresentInSnapshot() throws {
        let snapshot = OAuthCredentialSnapshot(
            accessToken: "new-access",
            refreshToken: "new-refresh",
            expiresAt: 1_999_999_999_999,
            scopes: ["user:inference"],
            subscriptionType: "pro",
            rateLimitTier: "default_claude_pro"
        )

        let merged = CredentialBlobCodec.merged(snapshot, into: Self.realisticBlob())
        let oauth = try #require(merged["claudeAiOauth"] as? [String: Any])

        #expect(oauth["accessToken"] as? String == "new-access")
        #expect(oauth["refreshToken"] as? String == "new-refresh")
        #expect(oauth["expiresAt"] as? Int64 == 1_999_999_999_999)
        #expect(oauth["scopes"] as? [String] == ["user:inference"])
        #expect(oauth["subscriptionType"] as? String == "pro")
        #expect(oauth["rateLimitTier"] as? String == "default_claude_pro")
        // Still untouched.
        #expect(oauth["refreshTokenExpiresAt"] as? Int == 1_787_556_898_642)
    }

    @Test func mergeCreatesOAuthSectionWhenAbsent() throws {
        let merged = CredentialBlobCodec.merged(
            OAuthCredentialSnapshot(accessToken: "new-access"),
            into: ["mcpOAuth": ["some": "thing"]]
        )

        let oauth = try #require(merged["claudeAiOauth"] as? [String: Any])
        #expect(oauth["accessToken"] as? String == "new-access")
        #expect((merged["mcpOAuth"] as? [String: Any])?["some"] as? String == "thing")
    }

    @Test func mergeRoundTripsThroughSerialization() throws {
        let merged = CredentialBlobCodec.merged(
            OAuthCredentialSnapshot(accessToken: "new-access", refreshToken: "new-refresh"),
            into: Self.realisticBlob()
        )
        let data = try #require(CredentialBlobCodec.serialize(merged))
        let reparsed = try #require(CredentialBlobCodec.jsonObject(fromData: data))

        let snapshot = try #require(CredentialBlobCodec.snapshot(fromJSONObject: reparsed))
        #expect(snapshot.accessToken == "new-access")
        #expect(snapshot.refreshToken == "new-refresh")
        #expect(reparsed["mcpOAuth"] != nil)
    }

    @Test func jsonObjectReturnsNilForNonObjectJSON() {
        #expect(CredentialBlobCodec.jsonObject(fromRawString: "[1,2,3]") == nil)
        #expect(CredentialBlobCodec.jsonObject(fromRawString: "not json") == nil)
    }

    // MARK: - Fixture

    /// Mirrors the real shape of `~/.claude/.credentials.json`, including the
    /// `mcpOAuth` sibling and the `refreshTokenExpiresAt` field this app does not
    /// model.
    static func realisticBlob() -> [String: Any] {
        [
            "claudeAiOauth": [
                "accessToken": "access-abc",
                "refreshToken": "refresh-xyz",
                "expiresAt": 1_785_163_669_642,
                "refreshTokenExpiresAt": 1_787_556_898_642,
                "scopes": ["user:inference", "user:profile"],
                "subscriptionType": "max",
                "rateLimitTier": "default_claude_max_20x",
            ],
            "mcpOAuth": [
                "linear-server|638130d5ab3558f4": [
                    "serverName": "linear-server",
                    "serverUrl": "https://mcp.linear.app",
                    "accessToken": "mcp-access",
                    "clientId": "mcp-client-id",
                    "clientSecret": "mcp-client-secret",
                    "redirectUri": "http://localhost:54545/callback",
                    "discoveryState": [
                        "authorizationServerUrl": "https://linear.app",
                        "resourceMetadataUrl": "https://mcp.linear.app/.well-known/x",
                        "oauthMetadataFound": true,
                    ],
                ],
            ],
        ]
    }
}
