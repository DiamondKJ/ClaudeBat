import Foundation
import OSLog

public actor MonitorService: AppMonitoring {
    private let buildInfo: AppBuildInfo
    private let fileManager: FileManager
    private let logsDirectory: URL
    private let appSupportDirectory: URL
    private let eventLogURL: URL
    private let statusURL: URL
    private let maxLogBytes: Int
    private let maxLogFiles: Int
    private let logger: Logger
    private var latestKnownStatus: MonitorStatus?

    public init(
        buildInfo: AppBuildInfo = .current,
        fileManager: FileManager = .default,
        logsDirectory: URL? = nil,
        appSupportDirectory: URL? = nil,
        maxLogBytes: Int = 5 * 1024 * 1024,
        maxLogFiles: Int = 5
    ) {
        self.buildInfo = buildInfo
        self.fileManager = fileManager

        let libraryRoot = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library", isDirectory: true)
        self.logsDirectory = logsDirectory
            ?? libraryRoot.appendingPathComponent("Logs/ClaudeBat", isDirectory: true)
        self.appSupportDirectory = appSupportDirectory
            ?? libraryRoot.appendingPathComponent("Application Support/ClaudeBat", isDirectory: true)
        self.eventLogURL = self.logsDirectory.appendingPathComponent("monitor.jsonl")
        self.statusURL = self.appSupportDirectory.appendingPathComponent("monitor-status.json")
        self.maxLogBytes = maxLogBytes
        self.maxLogFiles = max(2, maxLogFiles)
        self.logger = Logger(subsystem: buildInfo.bundleIdentifier, category: "monitor")
    }

    public func record(event: MonitorEvent, status: MonitorStatus) {
        latestKnownStatus = status
        let record = MonitorEventRecord(event: event, status: status, buildInfo: buildInfo)

        logger.log(level: record.logLevel, "\(record.summary, privacy: .public)")

        do {
            try ensureDirectories()
            try append(record: record)
            try write(status: status)
        } catch {
            logger.error("monitor_write_failed")
        }
    }

    public func latestStatus() -> MonitorStatus? {
        latestKnownStatus
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
    }

    private func append(record: MonitorEventRecord) throws {
        let data = try makeEncoder().encode(record)
        try rotateIfNeeded(forAdditionalBytes: data.count + 1)

        if !fileManager.fileExists(atPath: eventLogURL.path) {
            fileManager.createFile(atPath: eventLogURL.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: eventLogURL)
        defer { try? handle.close() }
        try handle.seekToEnd()

        var line = data
        line.append(0x0A)
        try handle.write(contentsOf: line)
    }

    private func write(status: MonitorStatus) throws {
        let data = try makeEncoder(prettyPrinted: true).encode(status)
        try data.write(to: statusURL, options: .atomic)
    }

    private func rotateIfNeeded(forAdditionalBytes additionalBytes: Int) throws {
        guard fileManager.fileExists(atPath: eventLogURL.path) else { return }

        let currentSize = (try? fileManager.attributesOfItem(atPath: eventLogURL.path)[.size] as? NSNumber)?.intValue ?? 0
        guard currentSize + additionalBytes > maxLogBytes else { return }

        let maxArchiveIndex = maxLogFiles - 1
        let oldestArchive = archiveURL(index: maxArchiveIndex)
        if fileManager.fileExists(atPath: oldestArchive.path) {
            try fileManager.removeItem(at: oldestArchive)
        }

        if maxArchiveIndex > 1 {
            for index in stride(from: maxArchiveIndex - 1, through: 1, by: -1) {
                let source = archiveURL(index: index)
                let destination = archiveURL(index: index + 1)
                if fileManager.fileExists(atPath: source.path) {
                    if fileManager.fileExists(atPath: destination.path) {
                        try fileManager.removeItem(at: destination)
                    }
                    try fileManager.moveItem(at: source, to: destination)
                }
            }
        }

        let firstArchive = archiveURL(index: 1)
        if fileManager.fileExists(atPath: firstArchive.path) {
            try fileManager.removeItem(at: firstArchive)
        }
        try fileManager.moveItem(at: eventLogURL, to: firstArchive)
    }

    private func archiveURL(index: Int) -> URL {
        eventLogURL.appendingPathExtension(String(index))
    }

    private func makeEncoder(prettyPrinted: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        return encoder
    }
}
