import Foundation

public struct AppBuildInfo: Equatable, Sendable {
    public let appVersion: String
    public let buildFlavor: String
    public let gitCommit: String
    public let bundleIdentifier: String

    public init(
        appVersion: String,
        buildFlavor: String,
        gitCommit: String,
        bundleIdentifier: String
    ) {
        self.appVersion = appVersion
        self.buildFlavor = buildFlavor
        self.gitCommit = gitCommit
        self.bundleIdentifier = bundleIdentifier
    }

    public static var current: AppBuildInfo {
        let info = Bundle.main.infoDictionary ?? [:]
        let env = ProcessInfo.processInfo.environment

        let appVersion = (info["CFBundleShortVersionString"] as? String)
            ?? env["CB_APP_VERSION"]
            ?? "dev"
        let buildFlavor = (info["CBBuildFlavor"] as? String)
            ?? env["CB_BUILD_FLAVOR"]
            ?? "standard"
        let gitCommit = (info["CBGitCommit"] as? String)
            ?? env["CB_GIT_COMMIT"]
            ?? "unknown"
        let bundleIdentifier = Bundle.main.bundleIdentifier
            ?? (info["CFBundleIdentifier"] as? String)
            ?? "com.diamondkj.claudebat"

        return AppBuildInfo(
            appVersion: appVersion,
            buildFlavor: buildFlavor,
            gitCommit: gitCommit,
            bundleIdentifier: bundleIdentifier
        )
    }

    public var isLocalMonitorBuild: Bool {
        buildFlavor == "local-monitor"
    }

    public var shortGitCommit: String {
        guard gitCommit != "unknown" else { return gitCommit }
        return String(gitCommit.prefix(7))
    }

    public var aboutBuildLine: String? {
        guard isLocalMonitorBuild else { return nil }
        return "Local monitor build (\(shortGitCommit))"
    }
}
