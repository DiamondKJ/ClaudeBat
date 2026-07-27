import Testing
import Foundation
@testable import ClaudeBatCore

@Suite("CredentialStore")
struct CredentialStoreTests {

    /// Instrumented source: counts reads so we can assert the Keychain subprocess is
    /// not spawned when the file already has a usable credential.
    final class FakeSource: TokenProvider, @unchecked Sendable {
        var snapshot: OAuthCredentialSnapshot?
        var source: CredentialSource
        var exists: Bool
        var writeSucceeds = true
        var readCount = 0
        var writtenSnapshots: [OAuthCredentialSnapshot] = []

        init(
            snapshot: OAuthCredentialSnapshot? = nil,
            source: CredentialSource = .credentialsFile,
            exists: Bool? = nil
        ) {
            self.snapshot = snapshot
            self.source = source
            self.exists = exists ?? (snapshot != nil)
        }

        func readToken() -> String? { readOAuthSnapshot()?.accessToken }

        func readOAuthSnapshot() -> OAuthCredentialSnapshot? {
            readCount += 1
            return snapshot
        }

        @discardableResult
        func writeOAuthSnapshot(_ snapshot: OAuthCredentialSnapshot) -> Bool {
            writtenSnapshots.append(snapshot)
            guard writeSucceeds else { return false }
            self.snapshot = snapshot
            return true
        }

        func credentialSource() -> CredentialSource? { snapshot == nil ? nil : source }
        var storeExists: Bool { exists }
        func credentialProbeSummary() -> String {
            "\(source.rawValue)=\(exists ? "present" : "absent")"
        }
    }

    private static let reference = Date(timeIntervalSince1970: 1_785_000_000)

    private func milliseconds(offsetFromReference offset: TimeInterval) -> Int64 {
        Int64((Self.reference.timeIntervalSince1970 + offset) * 1000)
    }

    private func store(
        _ sources: [any TokenProvider],
        expirySkew: TimeInterval = 60
    ) -> CredentialStore {
        CredentialStore(sources: sources, expirySkew: expirySkew, now: { Self.reference })
    }

    private func valid(_ token: String, refreshToken: String? = "refresh") -> OAuthCredentialSnapshot {
        OAuthCredentialSnapshot(
            accessToken: token,
            refreshToken: refreshToken,
            expiresAt: milliseconds(offsetFromReference: 3600)
        )
    }

    private func expired(
        _ token: String,
        refreshToken: String? = "refresh",
        secondsAgo: TimeInterval = 3600
    ) -> OAuthCredentialSnapshot {
        OAuthCredentialSnapshot(
            accessToken: token,
            refreshToken: refreshToken,
            expiresAt: milliseconds(offsetFromReference: -secondsAgo)
        )
    }

    // MARK: - Read precedence

    @Test func prefersFileWhenBothAreValid() {
        let file = FakeSource(snapshot: valid("file-token"), source: .credentialsFile)
        let keychain = FakeSource(snapshot: valid("keychain-token"), source: .keychain)

        let store = store([file, keychain])
        #expect(store.readToken() == "file-token")
        #expect(store.credentialSource() == .credentialsFile)
    }

    /// Guards the perf regression: `ClaudeCLIRecoveryService` polls every 0.5s and a
    /// Keychain read spawns `/usr/bin/security`.
    @Test func doesNotProbeLowerPrioritySourceWhenTopSourceIsUsable() {
        let file = FakeSource(snapshot: valid("file-token"))
        let keychain = FakeSource(snapshot: valid("keychain-token"), source: .keychain)

        _ = store([file, keychain]).readOAuthSnapshot()
        #expect(keychain.readCount == 0)
    }

    @Test func prefersKeychainWhenFileTokenIsExpired() {
        let file = FakeSource(snapshot: expired("file-token"))
        let keychain = FakeSource(snapshot: valid("keychain-token"), source: .keychain)

        let store = store([file, keychain])
        #expect(store.readToken() == "keychain-token")
        #expect(store.credentialSource() == .keychain)
    }

    @Test func fallsBackToKeychainWhenFileHasNoCredentials() {
        let file = FakeSource(snapshot: nil)
        let keychain = FakeSource(snapshot: valid("keychain-token"), source: .keychain)

        #expect(store([file, keychain]).readToken() == "keychain-token")
    }

    @Test func treatsSnapshotWithUnknownExpiryAsUsable() {
        // A bare token from a hand-created Keychain entry has no expiry; the only way
        // to find out if it works is to use it.
        let file = FakeSource(snapshot: OAuthCredentialSnapshot(accessToken: "bare"))
        let keychain = FakeSource(snapshot: valid("keychain-token"), source: .keychain)

        #expect(store([file, keychain]).readToken() == "bare")
    }

    @Test func treatsTokenExpiringInsideSkewWindowAsUnusable() {
        let file = FakeSource(
            snapshot: OAuthCredentialSnapshot(
                accessToken: "about-to-die",
                refreshToken: "r",
                expiresAt: milliseconds(offsetFromReference: 30)
            )
        )
        let keychain = FakeSource(snapshot: valid("keychain-token"), source: .keychain)

        #expect(store([file, keychain], expirySkew: 60).readToken() == "keychain-token")
    }

    // MARK: - Repair-candidate selection when everything is expired

    @Test func prefersLaterExpiryWhenBothExpired() {
        let file = FakeSource(snapshot: expired("file-token", secondsAgo: 7200))
        let keychain = FakeSource(snapshot: expired("keychain-token", secondsAgo: 60), source: .keychain)

        #expect(store([file, keychain]).readToken() == "keychain-token")
    }

    @Test func prefersRefreshableWhenBothExpiredAtSameTime() {
        let file = FakeSource(snapshot: expired("file-token", refreshToken: nil))
        let keychain = FakeSource(snapshot: expired("keychain-token", refreshToken: "r"), source: .keychain)

        #expect(store([file, keychain]).readToken() == "keychain-token")
    }

    @Test func prefersFileWhenExpiredCandidatesAreIdentical() {
        let file = FakeSource(snapshot: expired("file-token"))
        let keychain = FakeSource(snapshot: expired("keychain-token"), source: .keychain)

        #expect(store([file, keychain]).readToken() == "file-token")
    }

    @Test func returnsNilWhenNoSourceHasCredentials() {
        let store = store([FakeSource(snapshot: nil), FakeSource(snapshot: nil, source: .keychain)])

        #expect(store.readOAuthSnapshot() == nil)
        #expect(store.readToken() == nil)
        #expect(store.credentialSource() == nil)
    }

    // MARK: - Write routing

    @Test func routesWriteToTheResolvedSource() {
        let file = FakeSource(snapshot: valid("file-token"))
        let keychain = FakeSource(snapshot: valid("keychain-token"), source: .keychain)

        #expect(store([file, keychain]).writeOAuthSnapshot(valid("rotated")))
        #expect(file.writtenSnapshots.map(\.accessToken) == ["rotated"])
        #expect(keychain.writtenSnapshots.isEmpty)
    }

    /// The read/write agreement invariant: if reads come from the Keychain, a
    /// refreshed token must be persisted there too, or every refresh is a silent
    /// no-op that repeats forever.
    @Test func routesWriteToKeychainWhenKeychainWonResolution() {
        let file = FakeSource(snapshot: expired("file-token"))
        let keychain = FakeSource(snapshot: valid("keychain-token"), source: .keychain)

        #expect(store([file, keychain]).writeOAuthSnapshot(valid("rotated")))
        #expect(keychain.writtenSnapshots.map(\.accessToken) == ["rotated"])
        #expect(file.writtenSnapshots.isEmpty)
    }

    @Test func writeFailureDoesNotFanOutToOtherSource() {
        let file = FakeSource(snapshot: valid("file-token"))
        file.writeSucceeds = false
        let keychain = FakeSource(snapshot: valid("keychain-token"), source: .keychain)

        #expect(!store([file, keychain]).writeOAuthSnapshot(valid("rotated")))
        #expect(keychain.writtenSnapshots.isEmpty)
    }

    @Test func writeFallsBackToFirstExistingStoreWhenNothingResolves() {
        // File exists but holds nothing usable; Keychain doesn't exist at all.
        let file = FakeSource(snapshot: nil, exists: true)
        let keychain = FakeSource(snapshot: nil, source: .keychain, exists: false)

        #expect(store([file, keychain]).writeOAuthSnapshot(valid("fresh")))
        #expect(file.writtenSnapshots.map(\.accessToken) == ["fresh"])
        #expect(keychain.writtenSnapshots.isEmpty)
    }

    @Test func writeReturnsFalseAndTouchesNothingWhenNoStoreExists() {
        let file = FakeSource(snapshot: nil, exists: false)
        let keychain = FakeSource(snapshot: nil, source: .keychain, exists: false)

        #expect(!store([file, keychain]).writeOAuthSnapshot(valid("fresh")))
        #expect(file.writtenSnapshots.isEmpty)
        #expect(keychain.writtenSnapshots.isEmpty)
        #expect(!store([file, keychain]).storeExists)
    }

    // MARK: - Diagnostics

    @Test func probeSummaryNamesEachStoreAndWhetherItExists() {
        let file = FakeSource(snapshot: nil, exists: false)
        let keychain = FakeSource(snapshot: valid("keychain-token"), source: .keychain)

        let summary = store([file, keychain]).credentialProbeSummary()
        #expect(summary == "credentials_file=absent keychain=present")
    }

    // MARK: - Real components composed together

    @Test func resolvesThroughRealFileServiceWhenKeychainIsEmpty() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(".credentials.json")
        try JSONSerialization
            .data(withJSONObject: CredentialBlobCodecTests.realisticBlob())
            .write(to: url)

        // No expiry skew games: the fixture's expiresAt is in 2026, so pin `now`
        // before it.
        let store = CredentialStore(
            sources: [CredentialFileService(fileURL: url)],
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        #expect(store.readToken() == "access-abc")
        #expect(store.credentialSource() == .credentialsFile)
        #expect(store.storeExists)
    }
}
