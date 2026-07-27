import Testing
import Foundation
@testable import ClaudeBatCore

@Suite("CredentialFileService")
struct CredentialFileServiceTests {

    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes the realistic fixture (mcpOAuth sibling + refreshTokenExpiresAt) at 0600.
    private func seedCredentials(
        in directory: URL,
        blob: [String: Any]? = nil,
        permissions: Int = 0o600
    ) throws -> URL {
        let url = directory.appendingPathComponent(".credentials.json")
        let data = try JSONSerialization.data(
            withJSONObject: blob ?? CredentialBlobCodecTests.realisticBlob()
        )
        #expect(FileManager.default.createFile(
            atPath: url.path,
            contents: data,
            attributes: [.posixPermissions: NSNumber(value: permissions)]
        ))
        return url
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attributes[.posixPermissions] as? NSNumber).intValue
    }

    private func json(at url: URL) throws -> [String: Any] {
        let data = try #require(FileManager.default.contents(atPath: url.path))
        return try #require(CredentialBlobCodec.jsonObject(fromData: data))
    }

    // MARK: - Read

    @Test func readsSnapshotFromRealisticFile() throws {
        let directory = try tempDirectory()
        let url = try seedCredentials(in: directory)
        let service = CredentialFileService(fileURL: url)

        let snapshot = try #require(service.readOAuthSnapshot())
        #expect(snapshot.accessToken == "access-abc")
        #expect(snapshot.refreshToken == "refresh-xyz")
        #expect(snapshot.expiresAt == 1_785_163_669_642)
        #expect(snapshot.subscriptionType == "max")
        #expect(service.readToken() == "access-abc")
        #expect(service.tokenFingerprint() == snapshot.fingerprint)
        #expect(service.credentialSource() == .credentialsFile)
        #expect(service.storeExists)
    }

    @Test func returnsNilWhenFileMissing() throws {
        let directory = try tempDirectory()
        let service = CredentialFileService(
            fileURL: directory.appendingPathComponent(".credentials.json")
        )

        #expect(service.readOAuthSnapshot() == nil)
        #expect(service.readToken() == nil)
        #expect(service.credentialSource() == nil)
        #expect(!service.storeExists)
    }

    @Test func returnsNilWhenFileIsNotJSON() throws {
        let directory = try tempDirectory()
        let url = directory.appendingPathComponent(".credentials.json")
        try Data("not json at all".utf8).write(to: url)
        let service = CredentialFileService(fileURL: url)

        #expect(service.readOAuthSnapshot() == nil)
        // The file exists even though it holds nothing usable — the distinction
        // matters for CredentialStore's write routing.
        #expect(service.storeExists)
    }

    @Test func returnsNilWhenOAuthSectionIsAbsent() throws {
        let directory = try tempDirectory()
        let url = try seedCredentials(in: directory, blob: ["mcpOAuth": ["a": "b"]])
        let service = CredentialFileService(fileURL: url)

        #expect(service.readOAuthSnapshot() == nil)
    }

    // MARK: - Write safety
    //
    // These are the tests standing between this app and destroying the user's
    // Claude Code login plus every MCP credential they hold.

    @Test func writePreservesMcpOAuthSection() throws {
        let directory = try tempDirectory()
        let url = try seedCredentials(in: directory)
        let service = CredentialFileService(fileURL: url)

        #expect(service.writeOAuthSnapshot(OAuthCredentialSnapshot(accessToken: "rotated")))

        let root = try json(at: url)
        let mcp = try #require(root["mcpOAuth"] as? [String: Any])
        let server = try #require(mcp["linear-server|638130d5ab3558f4"] as? [String: Any])
        #expect(server["clientSecret"] as? String == "mcp-client-secret")
        #expect(server["accessToken"] as? String == "mcp-access")
        let discovery = try #require(server["discoveryState"] as? [String: Any])
        #expect(discovery["oauthMetadataFound"] as? Bool == true)
    }

    @Test func writePreservesRefreshTokenExpiresAt() throws {
        let directory = try tempDirectory()
        let url = try seedCredentials(in: directory)
        let service = CredentialFileService(fileURL: url)

        #expect(service.writeOAuthSnapshot(OAuthCredentialSnapshot(accessToken: "rotated")))

        let oauth = try #require(try json(at: url)["claudeAiOauth"] as? [String: Any])
        #expect(oauth["refreshTokenExpiresAt"] as? Int == 1_787_556_898_642)
        // And the fields the partial snapshot didn't carry are still intact.
        #expect(oauth["refreshToken"] as? String == "refresh-xyz")
        #expect(oauth["subscriptionType"] as? String == "max")
    }

    @Test func writePreserves0600Permissions() throws {
        let directory = try tempDirectory()
        let url = try seedCredentials(in: directory, permissions: 0o600)
        let service = CredentialFileService(fileURL: url)

        #expect(service.writeOAuthSnapshot(OAuthCredentialSnapshot(accessToken: "rotated")))
        #expect(try permissions(of: url) == 0o600)
    }

    /// This is the test that fails if anyone replaces the temp-file+rename with
    /// `Data.write(to:options: .atomic)` — that would take the mode from the umask
    /// (0644) and leak the refresh token to every user on the machine.
    @Test func writePreservesNonDefaultPermissions() throws {
        let directory = try tempDirectory()
        let url = try seedCredentials(in: directory, permissions: 0o640)
        let service = CredentialFileService(fileURL: url)

        #expect(service.writeOAuthSnapshot(OAuthCredentialSnapshot(accessToken: "rotated")))
        #expect(try permissions(of: url) == 0o640)
    }

    @Test func writeCreatesFileWith0600WhenAbsent() throws {
        let directory = try tempDirectory()
        let url = directory.appendingPathComponent(".credentials.json")
        let service = CredentialFileService(fileURL: url)

        #expect(service.writeOAuthSnapshot(OAuthCredentialSnapshot(accessToken: "fresh")))
        #expect(try permissions(of: url) == 0o600)
        #expect(service.readToken() == "fresh")
    }

    @Test func writeRefusesWhenExistingFileIsCorrupt() throws {
        let directory = try tempDirectory()
        let url = directory.appendingPathComponent(".credentials.json")
        let garbage = Data("{ this is not valid json".utf8)
        try garbage.write(to: url)
        let service = CredentialFileService(fileURL: url)

        #expect(!service.writeOAuthSnapshot(OAuthCredentialSnapshot(accessToken: "rotated")))
        // Byte-identical afterwards — we wrote nothing at all.
        #expect(FileManager.default.contents(atPath: url.path) == garbage)
    }

    @Test func writeRefusesWhenDirectoryDoesNotExist() throws {
        let directory = try tempDirectory()
        let service = CredentialFileService(
            fileURL: directory
                .appendingPathComponent("nope", isDirectory: true)
                .appendingPathComponent(".credentials.json")
        )

        #expect(!service.writeOAuthSnapshot(OAuthCredentialSnapshot(accessToken: "fresh")))
    }

    @Test func writeLeavesNoTemporaryFiles() throws {
        let directory = try tempDirectory()
        let url = try seedCredentials(in: directory)
        let service = CredentialFileService(fileURL: url)

        for index in 0..<20 {
            #expect(service.writeOAuthSnapshot(OAuthCredentialSnapshot(accessToken: "tok-\(index)")))
            // Still parseable after every single write.
            #expect(service.readToken() == "tok-\(index)")
        }

        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(contents == [".credentials.json"])
    }

    @Test func roundTripsFullSnapshot() throws {
        let directory = try tempDirectory()
        let url = try seedCredentials(in: directory)
        let service = CredentialFileService(fileURL: url)
        let snapshot = OAuthCredentialSnapshot(
            accessToken: "new-access",
            refreshToken: "new-refresh",
            expiresAt: 1_999_999_999_999,
            scopes: ["user:inference"],
            subscriptionType: "pro",
            rateLimitTier: "default_claude_pro"
        )

        #expect(service.writeOAuthSnapshot(snapshot))
        #expect(service.readOAuthSnapshot() == snapshot)
    }

    // MARK: - Symlinks (dotfile managers do this)

    @Test func readsThroughSymlink() throws {
        let directory = try tempDirectory()
        let real = try seedCredentials(in: directory)
        let link = directory.appendingPathComponent("linked.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let service = CredentialFileService(fileURL: link)
        #expect(service.readToken() == "access-abc")
    }

    @Test func writeReplacesSymlinkTargetAndKeepsLinkIntact() throws {
        let directory = try tempDirectory()
        let real = try seedCredentials(in: directory)
        let link = directory.appendingPathComponent("linked.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let service = CredentialFileService(fileURL: link)
        #expect(service.writeOAuthSnapshot(OAuthCredentialSnapshot(accessToken: "rotated")))

        // The real file received the update...
        let oauth = try #require(try json(at: real)["claudeAiOauth"] as? [String: Any])
        #expect(oauth["accessToken"] as? String == "rotated")
        // ...and the symlink is still a symlink pointing at it, not a regular file.
        let type = try FileManager.default.attributesOfItem(atPath: link.path)[.type] as? FileAttributeType
        #expect(type == .typeSymbolicLink)
        #expect(try permissions(of: real) == 0o600)
    }
}
