import Testing
import Foundation
@testable import ClaudeBatCore

@Suite("MonitorService")
struct MonitorServiceTests {

    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func writesStatusSnapshotAndJsonlEvent() async throws {
        let root = try tempDirectory()
        let logs = root.appendingPathComponent("logs", isDirectory: true)
        let support = root.appendingPathComponent("support", isDirectory: true)
        let buildInfo = AppBuildInfo(
            appVersion: "1.0.7",
            buildFlavor: "local-monitor",
            gitCommit: "abcdef123456",
            bundleIdentifier: "com.diamondkj.claudebat"
        )
        let service = MonitorService(
            buildInfo: buildInfo,
            logsDirectory: logs,
            appSupportDirectory: support,
            maxLogBytes: 1024,
            maxLogFiles: 3
        )

        let status = MonitorStatus(
            appRunning: true,
            displaySleeping: false,
            lastLaunchAt: Date(),
            lastAttemptAt: Date(),
            lastSuccessAt: Date(),
            lastFailureAt: Date(),
            lastFailureReason: FetchOutcome.http401.rawValue,
            lastHTTPStatus: 401,
            consecutiveFailures: 2,
            currentPollIntervalSeconds: 120,
            usingCachedData: true,
            cacheAgeSeconds: 901,
            sessionResetsAt: Date().addingTimeInterval(1800),
            sessionRemaining: 44,
            lastWakeAt: Date(),
            lastWakeSource: .machine,
            buildFlavor: buildInfo.buildFlavor,
            gitCommit: buildInfo.gitCommit,
            staleReason: .authInvalid
        )

        await service.record(
            event: MonitorEvent(
                category: .fetch,
                action: "completed",
                trigger: .pollTimer,
                outcome: .http401,
                message: "usage endpoint returned 401"
            ),
            status: status
        )

        let statusURL = support.appendingPathComponent("monitor-status.json")
        let logURL = logs.appendingPathComponent("monitor.jsonl")

        let statusData = try Data(contentsOf: statusURL)
        let statusDecoder = JSONDecoder()
        statusDecoder.dateDecodingStrategy = .iso8601
        let decodedStatus = try statusDecoder.decode(MonitorStatus.self, from: statusData)
        #expect(decodedStatus.appRunning)
        #expect(decodedStatus.pid > 0)
        #expect(decodedStatus.staleReason == .authInvalid)
        #expect(decodedStatus.lastHTTPStatus == 401)

        let logData = try String(contentsOf: logURL)
        let lines = logData.split(separator: "\n")
        #expect(lines.count == 1)
        let recordDecoder = JSONDecoder()
        recordDecoder.dateDecodingStrategy = .iso8601
        let record = try recordDecoder.decode(MonitorEventRecord.self, from: Data(lines[0].utf8))
        #expect(record.outcome == FetchOutcome.http401.rawValue)
        #expect(record.statusPID == decodedStatus.pid)
        #expect(record.buildFlavor == "local-monitor")
        #expect(record.gitCommit == "abcdef123456")
        #expect(record.usingCachedData)
    }

    @Test func rotatesLogFilesWhenSizeExceeded() async throws {
        let root = try tempDirectory()
        let logs = root.appendingPathComponent("logs", isDirectory: true)
        let support = root.appendingPathComponent("support", isDirectory: true)
        let buildInfo = AppBuildInfo(
            appVersion: "1.0.7",
            buildFlavor: "local-monitor",
            gitCommit: "abcdef123456",
            bundleIdentifier: "com.diamondkj.claudebat"
        )
        let service = MonitorService(
            buildInfo: buildInfo,
            logsDirectory: logs,
            appSupportDirectory: support,
            maxLogBytes: 300,
            maxLogFiles: 3
        )

        for index in 0..<12 {
            let status = MonitorStatus(
                appRunning: true,
                currentPollIntervalSeconds: 120,
                buildFlavor: buildInfo.buildFlavor,
                gitCommit: buildInfo.gitCommit
            )
            await service.record(
                event: MonitorEvent(
                    category: .fetch,
                    action: "completed",
                    trigger: .pollTimer,
                    outcome: .success,
                    message: "rotation test event \(index) with padding 0123456789"
                ),
                status: status
            )
        }

        #expect(FileManager.default.fileExists(atPath: logs.appendingPathComponent("monitor.jsonl").path))
        #expect(FileManager.default.fileExists(atPath: logs.appendingPathComponent("monitor.jsonl.1").path))
        #expect(FileManager.default.fileExists(atPath: logs.appendingPathComponent("monitor.jsonl.2").path))
        #expect(!FileManager.default.fileExists(atPath: logs.appendingPathComponent("monitor.jsonl.3").path))
    }
}
