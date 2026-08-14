import AppKit
import SwiftUI
import Testing
@testable import ClaudeBatCore

private final class PopoverRootTestBundleMarker: NSObject {}

@MainActor
private struct RootMeasurement {
    let preferred: CGSize
    let fitting: [CGFloat: CGSize]
}

@MainActor
private enum PopoverRootHarness {
    static let allocations: [CGFloat] = [392, 472, 1_000, 10_000]
    static let proposals: [CGFloat] = [392, 472, 1_000, 10_000]

    static func normal(
        _ usage: UsageResponse,
        cachedReason: CachedDataReason? = nil
    ) -> AnyView {
        AnyView(
            NormalPopoverRoot(onClose: {}) {
                VStack(spacing: 0) {
                    if let cachedReason {
                        CachedDataBanner(reason: cachedReason)
                        Spacer().frame(height: 12)
                    }
                    NormalUsageView(usage: usage)
                    Spacer().frame(height: CBPopoverMetrics.lowerSectionSpacing)
                    FreshnessIndicator(
                        fetchedAt: PopoverLayoutFixture.fetchedAt,
                        freshness: .fresh
                    )
                }
            }
            .popoverDisplayEnvironment(PopoverLayoutFixture.displayEnvironment)
        )
    }

    static func error(_ message: String) -> AnyView {
        AnyView(
            HeaderBaselinePopoverRoot(
                onClose: {},
                hasBanner: false,
                hasFooter: false,
                banner: { EmptyView() },
                stateContent: { ErrorView(message: message) },
                footer: { EmptyView() }
            )
            .popoverDisplayEnvironment(PopoverLayoutFixture.displayEnvironment)
        )
    }

    static func loading(message: String? = nil) -> AnyView {
        AnyView(
            StandaloneBaselinePopoverRoot {
                LoadingRetroView(title: message == nil ? "LOADING" : "SYNCING", message: message)
            }
            .popoverDisplayEnvironment(PopoverLayoutFixture.displayEnvironment)
        )
    }

    static func noAuth(installed: Bool) -> AnyView {
        let environment = PopoverDisplayEnvironment(
            fixedNow: PopoverLayoutFixture.referenceDate,
            timeZone: PopoverLayoutFixture.utc,
            claudeInstalled: installed
        )
        return AnyView(
            HeaderBaselinePopoverRoot(
                onClose: {},
                hasBanner: false,
                hasFooter: false,
                banner: { EmptyView() },
                stateContent: { NoAuthView(mode: .reconnect) },
                footer: { EmptyView() }
            )
            .popoverDisplayEnvironment(environment)
        )
    }

    static func gameOver(
        _ usage: UsageResponse,
        cachedReason: CachedDataReason? = nil
    ) -> AnyView {
        AnyView(
            HeaderBaselinePopoverRoot(
                onClose: {},
                hasBanner: cachedReason != nil,
                hasFooter: true,
                banner: {
                    if let cachedReason {
                        CachedDataBanner(reason: cachedReason)
                    }
                },
                stateContent: { GameOverView(usage: usage) },
                footer: {
                    FreshnessIndicator(
                        fetchedAt: PopoverLayoutFixture.fetchedAt,
                        freshness: .fresh
                    )
                }
            )
            .popoverDisplayEnvironment(PopoverLayoutFixture.displayEnvironment)
        )
    }

    static func routed(_ viewModel: UsageViewModel) -> AnyView {
        AnyView(
            UsagePopoverView(viewModel: viewModel)
                .popoverDisplayEnvironment(PopoverLayoutFixture.displayEnvironment)
        )
    }

    static func host(root: AnyView, allocation: CGFloat) -> NSHostingController<AnyView> {
        let host = NSHostingController(rootView: root)
        host.sizingOptions = [.preferredContentSize]
        host.loadView()
        host.view.frame = NSRect(
            x: 0,
            y: 0,
            width: CBPopoverMetrics.width,
            height: allocation
        )
        host.view.layoutSubtreeIfNeeded()
        return host
    }

    static func fittingHost(root: AnyView, allocation: CGFloat) -> NSHostingController<AnyView> {
        let host = NSHostingController(rootView: root)
        host.sizingOptions = []
        host.loadView()
        host.view.frame = NSRect(
            x: 0,
            y: 0,
            width: CBPopoverMetrics.width,
            height: allocation
        )
        host.view.layoutSubtreeIfNeeded()
        return host
    }

    static func finiteFittingSize(_ host: NSHostingController<AnyView>) -> CGSize {
        host.view.layoutSubtreeIfNeeded()
        return normalized(
            host.sizeThatFits(
                in: CGSize(
                    width: CBPopoverMetrics.width,
                    height: CBPopoverMetrics.measurementHeightProposal
                )
            )
        )
    }

    static func measure(_ host: NSHostingController<AnyView>) -> RootMeasurement {
        host.view.layoutSubtreeIfNeeded()
        let preferred = normalized(host.preferredContentSize)
        var fitting: [CGFloat: CGSize] = [:]
        for proposal in proposals {
            fitting[proposal] = normalized(
                host.sizeThatFits(
                    in: CGSize(width: CBPopoverMetrics.width, height: proposal)
                )
            )
        }
        return RootMeasurement(preferred: preferred, fitting: fitting)
    }

    static func measure(root: AnyView, allocation: CGFloat) -> RootMeasurement {
        let controller = host(root: root, allocation: allocation)
        defer { dispose(controller) }
        return measure(controller)
    }

    static func dispose(_ host: NSHostingController<AnyView>) {
        host.rootView = AnyView(EmptyView())
        host.sizingOptions = []
        host.view.layoutSubtreeIfNeeded()
        host.view.removeFromSuperview()
    }

    static func normalized(_ size: CGSize) -> CGSize {
        CGSize(
            width: (size.width * 2).rounded() / 2,
            height: (size.height * 2).rounded() / 2
        )
    }

    static func isFinitePositive(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }
}

@Suite(
    "Popover root fitting characterization",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["CB_RUN_APPKIT_LAYOUT_TESTS"] == "1")
)
struct PopoverRootCharacterizationTests {
    @MainActor
    @Test func normalRootIsAllocationIndependent() async {
        await Task.yield()
        FontRegistration.registerFonts(searchingFrom: Bundle(for: PopoverRootTestBundleMarker.self).bundleURL)
        let root = PopoverRootHarness.normal(PopoverLayoutFixture.compactUsage())
        var results: [RootMeasurement] = []
        for allocation in PopoverRootHarness.allocations {
            results.append(PopoverRootHarness.measure(root: root, allocation: allocation))
            await Task.yield()
        }

        for result in results {
            #expect(PopoverRootHarness.isFinitePositive(result.preferred))
            #expect(result.preferred.width == CBPopoverMetrics.width)
            for fit in result.fitting.values {
                #expect(fit == result.preferred)
            }
        }

        let baseline = results[0].preferred.height
        for result in results.dropFirst() {
            #expect(abs(result.preferred.height - baseline) <= 1)
        }
    }

    @MainActor
    @Test func retainedNormalHostRoundTripsCompactExpandedCompact() async {
        await Task.yield()
        FontRegistration.registerFonts(searchingFrom: Bundle(for: PopoverRootTestBundleMarker.self).bundleURL)
        let compact = PopoverRootHarness.normal(PopoverLayoutFixture.compactUsage())
        let expanded = PopoverRootHarness.normal(PopoverLayoutFixture.expandedUsage())
        let host = PopoverRootHarness.host(root: compact, allocation: 1_000)

        let firstCompact = PopoverRootHarness.measure(host).preferred.height
        await Task.yield()
        host.rootView = expanded
        let expandedHeight = PopoverRootHarness.measure(host).preferred.height
        await Task.yield()
        host.rootView = compact
        let finalCompact = PopoverRootHarness.measure(host).preferred.height
        PopoverRootHarness.dispose(host)

        #expect(expandedHeight > firstCompact + 1)
        #expect(abs(finalCompact - firstCompact) <= 1)
    }

    @MainActor
    @Test func canonicalBaselineRootsAre392AcrossAllocations() async {
        await Task.yield()
        FontRegistration.registerFonts(searchingFrom: Bundle(for: PopoverRootTestBundleMarker.self).bundleURL)
        let roots = [
            PopoverRootHarness.error("Unknown error"),
            PopoverRootHarness.loading(),
            PopoverRootHarness.gameOver(PopoverLayoutFixture.depletedUsage()),
        ]

        for root in roots {
            for allocation in PopoverRootHarness.allocations {
                let result = PopoverRootHarness.measure(root: root, allocation: allocation)
                #expect(result.preferred.width == CBPopoverMetrics.width)
                #expect(abs(result.preferred.height - CBPopoverMetrics.baselineHeight) <= 1)
                for fit in result.fitting.values {
                    #expect(fit == result.preferred)
                }
                await Task.yield()
            }
        }
    }

    @MainActor
    @Test func supportedNormalVariantsRemainAllocationIndependent() async {
        await Task.yield()
        FontRegistration.registerFonts(searchingFrom: Bundle(for: PopoverRootTestBundleMarker.self).bundleURL)
        let roots = [
            PopoverRootHarness.normal(PopoverLayoutFixture.compactUsage()),
            PopoverRootHarness.normal(PopoverLayoutFixture.expandedUsage()),
            PopoverRootHarness.normal(PopoverLayoutFixture.heavyUsage()),
        ]

        var naturalHeights: [CGFloat] = []
        for root in roots {
            var results: [RootMeasurement] = []
            for allocation in PopoverRootHarness.allocations {
                results.append(PopoverRootHarness.measure(root: root, allocation: allocation))
                await Task.yield()
            }
            let height = results[0].preferred.height
            naturalHeights.append(height)
            for result in results {
                #expect(result.preferred.width == CBPopoverMetrics.width)
                #expect(abs(result.preferred.height - height) <= 1)
                for fit in result.fitting.values {
                    #expect(fit == result.preferred)
                }
            }
        }

        #expect(naturalHeights[1] > naturalHeights[0] + 1)
        #expect(naturalHeights[2] > naturalHeights[1] + 1)
    }

    @MainActor
    @Test func cachedBannerRoundTripsOnOneRetainedHost() async {
        await Task.yield()
        FontRegistration.registerFonts(searchingFrom: Bundle(for: PopoverRootTestBundleMarker.self).bundleURL)
        let usage = PopoverLayoutFixture.compactUsage()
        let compact = PopoverRootHarness.normal(usage)
        let host = PopoverRootHarness.host(root: compact, allocation: 1_000)
        let baseline = PopoverRootHarness.measure(host).preferred.height

        for reason in [
            CachedDataReason.authInvalid,
            .noToken,
            .networkError,
            .serverError,
            .rateLimited,
        ] {
            host.rootView = PopoverRootHarness.normal(usage, cachedReason: reason)
            let bannerHeight = PopoverRootHarness.measure(host).preferred.height
            #expect(bannerHeight > baseline + 1)
            await Task.yield()

            host.rootView = compact
            let returnedHeight = PopoverRootHarness.measure(host).preferred.height
            #expect(abs(returnedHeight - baseline) <= 1)
            await Task.yield()
        }
        PopoverRootHarness.dispose(host)
    }

    @MainActor
    @Test func variableBaselineContentUses392AsAMinimum() async {
        await Task.yield()
        FontRegistration.registerFonts(searchingFrom: Bundle(for: PopoverRootTestBundleMarker.self).bundleURL)
        let extraGameOver = PopoverLayoutFixture.depletedUsage(
            extraUsage: ExtraUsage(
                isEnabled: true,
                monthlyLimit: 999_999,
                usedCredits: 999_999,
                utilization: 100
            )
        )
        let roots = [
            PopoverRootHarness.error(
                "The usage service returned an unexpected response.\nClaudeBat kept your synthetic data unchanged.\nTry the fixture again after the test resets."
            ),
            PopoverRootHarness.noAuth(installed: true),
            PopoverRootHarness.noAuth(installed: false),
            PopoverRootHarness.loading(message: "ClaudeBat is waiting for a clean synthetic usage response after the reset."),
            PopoverRootHarness.gameOver(extraGameOver),
            PopoverRootHarness.gameOver(extraGameOver, cachedReason: .networkError),
            PopoverRootHarness.gameOver(extraGameOver, cachedReason: .rateLimited),
        ]

        for root in roots {
            var results: [RootMeasurement] = []
            for allocation in PopoverRootHarness.allocations {
                results.append(PopoverRootHarness.measure(root: root, allocation: allocation))
                await Task.yield()
            }
            let height = results[0].preferred.height
            #expect(height >= CBPopoverMetrics.baselineHeight)
            for result in results {
                #expect(abs(result.preferred.height - height) <= 1)
                for fit in result.fitting.values {
                    #expect(fit == result.preferred)
                }
            }
        }
    }

    @MainActor
    @Test func routedUsagePopoverRoundTripsAndRoutesBaselineStates() async {
        await Task.yield()
        FontRegistration.registerFonts(searchingFrom: Bundle(for: PopoverRootTestBundleMarker.self).bundleURL)
        let fixture = PopoverLayoutFixture.makeLayoutViewModel()
        let host = PopoverRootHarness.fittingHost(
            root: PopoverRootHarness.routed(fixture.viewModel),
            allocation: 1_000
        )
        defer { PopoverRootHarness.dispose(host) }

        let compact = PopoverRootHarness.finiteFittingSize(host)
        fixture.viewModel.usage = PopoverLayoutFixture.expandedUsage()
        await Task.yield()
        let expanded = PopoverRootHarness.finiteFittingSize(host)
        fixture.viewModel.usage = PopoverLayoutFixture.compactUsage()
        await Task.yield()
        let returned = PopoverRootHarness.finiteFittingSize(host)

        #expect(compact == CGSize(width: 320, height: 327))
        #expect(expanded == CGSize(width: 320, height: 471))
        #expect(returned == compact)

        fixture.viewModel.usage = PopoverLayoutFixture.depletedUsage()
        await Task.yield()
        #expect(PopoverRootHarness.finiteFittingSize(host) == CGSize(width: 320, height: 392))

        fixture.viewModel.usage = nil
        fixture.viewModel.errorMessage = "Synthetic error"
        await Task.yield()
        #expect(PopoverRootHarness.finiteFittingSize(host) == CGSize(width: 320, height: 392))

        fixture.viewModel.errorMessage = nil
        await Task.yield()
        #expect(PopoverRootHarness.finiteFittingSize(host) == CGSize(width: 320, height: 392))
    }
}
