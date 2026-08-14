import AppKit
import Combine
import SwiftUI
import Testing
@testable import ClaudeBatCore

private final class PopoverSignalTestBundleMarker: NSObject {}

@MainActor
private final class SignalFixtureModel: ObservableObject {
    enum Mode {
        case normal
        case gameOver
        case error
        case loading
        case noAuthInstalled
        case noAuthMissing
    }

    @Published var usage = PopoverLayoutFixture.compactUsage()
    @Published var cachedReason: CachedDataReason?
    @Published var mode: Mode = .normal
}

@MainActor
private final class SignalLedger {
    private(set) var rawInvalidations = 0

    func recordInvalidation() {
        rawInvalidations += 1
    }
}

@MainActor
private final class SignalPopoverDelegate: NSObject, NSPopoverDelegate {
    private(set) var didShowCount = 0
    private(set) var didCloseCount = 0

    func popoverDidShow(_ notification: Notification) {
        didShowCount += 1
    }

    func popoverDidClose(_ notification: Notification) {
        didCloseCount += 1
    }
}

@MainActor
private struct SignalFixtureRoot: View {
    @ObservedObject var model: SignalFixtureModel
    let ledger: SignalLedger

    var body: some View {
        PopoverContentInvalidationSignal {
            ledger.recordInvalidation()
        } content: {
            finalRoot
        }
        .popoverDisplayEnvironment(PopoverLayoutFixture.displayEnvironment)
    }

    @ViewBuilder
    private var finalRoot: some View {
        switch model.mode {
        case .normal:
            NormalPopoverRoot(onClose: {}) {
                VStack(spacing: 0) {
                    if let cachedReason = model.cachedReason {
                        CachedDataBanner(reason: cachedReason)
                        Spacer().frame(height: 12)
                    }
                    NormalUsageView(usage: model.usage)
                    Spacer().frame(height: CBPopoverMetrics.lowerSectionSpacing)
                    FreshnessIndicator(
                        fetchedAt: PopoverLayoutFixture.fetchedAt,
                        freshness: .fresh
                    )
                }
            }
        case .gameOver:
            HeaderBaselinePopoverRoot(
                onClose: {},
                hasBanner: false,
                hasFooter: true,
                banner: { EmptyView() },
                stateContent: {
                    GameOverView(usage: PopoverLayoutFixture.depletedUsage())
                },
                footer: {
                    FreshnessIndicator(
                        fetchedAt: PopoverLayoutFixture.fetchedAt,
                        freshness: .fresh
                    )
                }
            )
        case .error:
            HeaderBaselinePopoverRoot(
                onClose: {},
                hasBanner: false,
                hasFooter: false,
                banner: { EmptyView() },
                stateContent: {
                    ErrorView(
                        message: "The synthetic usage service returned an unexpected response."
                    )
                },
                footer: { EmptyView() }
            )
        case .loading:
            StandaloneBaselinePopoverRoot {
                LoadingRetroView()
            }
        case .noAuthInstalled:
            HeaderBaselinePopoverRoot(
                onClose: {},
                hasBanner: false,
                hasFooter: false,
                banner: { EmptyView() },
                stateContent: { NoAuthView(mode: .reconnect, forceInstalled: true) },
                footer: { EmptyView() }
            )
        case .noAuthMissing:
            HeaderBaselinePopoverRoot(
                onClose: {},
                hasBanner: false,
                hasFooter: false,
                banner: { EmptyView() },
                stateContent: { NoAuthView(mode: .reconnect, forceInstalled: false) },
                footer: { EmptyView() }
            )
        }
    }
}

@MainActor
private enum SignalPopoverHarness {
    static func waitUntil(
        timeoutTurns: Int = 40,
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<timeoutTurns {
            if condition() { return true }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return condition()
    }

    static func settle(turns: Int = 4) async {
        for _ in 0..<turns {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}

@Suite(
    "Shown NSPopover invalidation signal characterization",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["CB_RUN_APPKIT_POPOVER_TESTS"] == "1")
)
struct PopoverSignalCharacterizationTests {
    @MainActor
    @Test func finalRootGeometrySignalsRealShapeChangesWithoutStableChurn() async throws {
        FontRegistration.registerFonts(searchingFrom: Bundle(for: PopoverSignalTestBundleMarker.self).bundleURL)
        let model = SignalFixtureModel()
        let ledger = SignalLedger()
        let root = SignalFixtureRoot(model: model, ledger: ledger)
        let host = NSHostingController(rootView: root)
        host.sizingOptions = []
        host.loadView()
        host.view.layoutSubtreeIfNeeded()

        let popover = NSPopover()
        let delegate = SignalPopoverDelegate()
        popover.delegate = delegate
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.contentViewController = host
        popover.contentSize = host.sizeThatFits(
            in: CGSize(width: CBPopoverMetrics.width, height: 10_000)
        )

        let screen = try #require(NSScreen.screens.first)
        let anchorWindow = NSWindow(
            contentRect: NSRect(
                x: screen.visibleFrame.midX,
                y: screen.visibleFrame.midY,
                width: 40,
                height: 20
            ),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        anchorWindow.isReleasedWhenClosed = false
        anchorWindow.level = .statusBar
        anchorWindow.backgroundColor = .clear
        anchorWindow.isOpaque = false
        let anchorView = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 20))
        anchorWindow.contentView = anchorView

        defer {
            if popover.isShown { popover.performClose(nil) }
            popover.delegate = nil
            popover.contentViewController = nil
            anchorWindow.orderOut(nil)
            anchorWindow.close()
            host.sizingOptions = []
            host.view.removeFromSuperview()
        }

        anchorWindow.orderFrontRegardless()
        popover.show(
            relativeTo: anchorView.bounds,
            of: anchorView,
            preferredEdge: .maxY
        )

        try #require(await SignalPopoverHarness.waitUntil { delegate.didShowCount == 1 })
        #expect(popover.isShown)

        await SignalPopoverHarness.settle()
        let stableCount = ledger.rawInvalidations
        await SignalPopoverHarness.settle(turns: 20)
        #expect(ledger.rawInvalidations == stableCount)

        let transitions = 100
        for index in 0..<transitions {
            let before = ledger.rawInvalidations
            model.usage = index.isMultiple(of: 2)
                ? PopoverLayoutFixture.expandedUsage()
                : PopoverLayoutFixture.compactUsage()
            try #require(await SignalPopoverHarness.waitUntil { ledger.rawInvalidations > before })
        }

        let beforeBanner = ledger.rawInvalidations
        model.cachedReason = .networkError
        try #require(await SignalPopoverHarness.waitUntil { ledger.rawInvalidations > beforeBanner })

        let beforeBannerRemoval = ledger.rawInvalidations
        model.cachedReason = nil
        try #require(await SignalPopoverHarness.waitUntil { ledger.rawInvalidations > beforeBannerRemoval })

        for mode in [
            SignalFixtureModel.Mode.gameOver,
            .error,
            .loading,
            .noAuthInstalled,
            .noAuthMissing,
        ] {
            let beforeTarget = ledger.rawInvalidations
            model.mode = mode
            try #require(await SignalPopoverHarness.waitUntil { ledger.rawInvalidations > beforeTarget })

            let beforeReturn = ledger.rawInvalidations
            model.mode = .normal
            model.usage = PopoverLayoutFixture.compactUsage()
            try #require(await SignalPopoverHarness.waitUntil { ledger.rawInvalidations > beforeReturn })
        }

        await SignalPopoverHarness.settle(turns: 20)
        let finalStableCount = ledger.rawInvalidations
        let expectedShapeChanges = transitions + 2 + (5 * 2)
        #expect(finalStableCount == stableCount + expectedShapeChanges)
        await SignalPopoverHarness.settle(turns: 20)
        #expect(ledger.rawInvalidations == finalStableCount)

        popover.performClose(nil)
        try #require(await SignalPopoverHarness.waitUntil { delegate.didCloseCount == 1 })
        #expect(!popover.isShown)
    }
}
