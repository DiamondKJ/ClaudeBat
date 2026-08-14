import AppKit
import Combine
import SwiftUI
import Testing
@testable import ClaudeBatCore

private final class PopoverLifecycleTestBundleMarker: NSObject {}

@MainActor
private final class LifecycleModel: ObservableObject {
    @Published var usage = PopoverLayoutFixture.compactUsage()
}

@MainActor
private final class LifecycleRelay {
    var onContentChanged: (() -> Void)?
    var onCloseRequested: (() -> Void)?
    private(set) var rawSignals = 0

    func contentChanged() {
        rawSignals += 1
        onContentChanged?()
    }

    func requestClose() {
        onCloseRequested?()
    }
}

@MainActor
private struct LifecycleRoot: View {
    @ObservedObject var model: LifecycleModel
    let relay: LifecycleRelay

    var body: some View {
        PopoverContentInvalidationSignal {
            relay.contentChanged()
        } content: {
            NormalPopoverRoot(onClose: relay.requestClose) {
                VStack(spacing: 0) {
                    NormalUsageView(usage: model.usage)
                    Spacer().frame(height: CBPopoverMetrics.lowerSectionSpacing)
                    FreshnessIndicator(
                        fetchedAt: PopoverLayoutFixture.fetchedAt,
                        freshness: .fresh
                    )
                }
            }
        }
        .popoverDisplayEnvironment(PopoverLayoutFixture.displayEnvironment)
    }
}

@MainActor
private final class LifecycleHarness {
    let model: LifecycleModel
    let relay: LifecycleRelay
    let host: NSHostingController<LifecycleRoot>
    let popover: NSPopover
    let coordinator: PopoverSizeCoordinator
    let driver: PopoverPresentationDriver
    let anchorWindow: NSWindow?
    let anchorView: NSView

    private(set) var sinkSizes: [CGSize] = []
    private(set) var preflightSizes: [CGSize] = []
    private(set) var willShowSizes: [CGSize] = []
    private(set) var didShowSizes: [CGSize] = []
    private(set) var showReturnSizes: [CGSize] = []
    private(set) var presentationOpenCount = 0
    private(set) var presentationCloseCount = 0
    private(set) var willCloseCount = 0
    private(set) var didCloseCount = 0

    init(
        visibleAnchor: Bool,
        measurementSucceeds: Bool = true,
        sinkSucceeds: Bool = true
    ) throws {
        let model = LifecycleModel()
        let relay = LifecycleRelay()
        let host = NSHostingController(rootView: LifecycleRoot(model: model, relay: relay))
        host.sizingOptions = []
        host.loadView()
        host.view.layoutSubtreeIfNeeded()

        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.contentViewController = host

        let anchorView = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 20))
        let anchorWindow: NSWindow?
        if visibleAnchor {
            let screen = try #require(NSScreen.screens.first)
            let window = NSWindow(
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
            window.isReleasedWhenClosed = false
            window.level = .statusBar
            window.backgroundColor = .clear
            window.isOpaque = false
            window.contentView = anchorView
            anchorWindow = window
        } else {
            anchorWindow = nil
        }

        var sinkRecorder: ((CGSize) -> Void)?
        var willShowRecorder: ((CGSize) -> Void)?
        var didShowRecorder: ((CGSize) -> Void)?
        var presentationOpenRecorder: (() -> Void)?
        var presentationCloseRecorder: (() -> Void)?
        var willCloseRecorder: (() -> Void)?
        var didCloseRecorder: (() -> Void)?
        let coordinator = PopoverSizeCoordinator(
            width: CBPopoverMetrics.width,
            measure: { [weak host] in
                guard measurementSucceeds, let host else { return nil }
                host.view.layoutSubtreeIfNeeded()
                return host.sizeThatFits(
                    in: CGSize(width: CBPopoverMetrics.width, height: 10_000)
                )
            },
            readCurrentSize: { [weak popover] in popover?.contentSize },
            applySize: { [weak popover] size in
                guard let popover else { return false }
                sinkRecorder?(size)
                guard sinkSucceeds else { return false }
                popover.contentSize = size
                return popover.contentSize == size
            }
        )
        let driver = PopoverPresentationDriver(
            popover: popover,
            coordinator: coordinator,
            onPresentationOpen: { presentationOpenRecorder?() },
            onPresentationClose: { presentationCloseRecorder?() },
            onWillShowSize: { size in willShowRecorder?(size) },
            onDidShowSize: { size in didShowRecorder?(size) },
            onWillClose: { willCloseRecorder?() },
            onDidClose: { didCloseRecorder?() }
        )

        self.model = model
        self.relay = relay
        self.host = host
        self.popover = popover
        self.coordinator = coordinator
        self.driver = driver
        self.anchorWindow = anchorWindow
        self.anchorView = anchorView

        sinkRecorder = { [weak self] size in self?.sinkSizes.append(size) }
        willShowRecorder = { [weak self] size in self?.willShowSizes.append(size) }
        didShowRecorder = { [weak self] size in self?.didShowSizes.append(size) }
        presentationOpenRecorder = { [weak self] in self?.presentationOpenCount += 1 }
        presentationCloseRecorder = { [weak self] in self?.presentationCloseCount += 1 }
        willCloseRecorder = { [weak self] in self?.willCloseCount += 1 }
        didCloseRecorder = { [weak self] in self?.didCloseCount += 1 }
        relay.onContentChanged = { [weak driver] in driver?.contentMayHaveChanged() }
        relay.onCloseRequested = { [weak driver] in driver?.requestClose() }
        anchorWindow?.orderFrontRegardless()
    }

    func open() -> Bool {
        host.view.layoutSubtreeIfNeeded()
        let measured = host.sizeThatFits(
            in: CGSize(
                width: CBPopoverMetrics.width,
                height: CBPopoverMetrics.measurementHeightProposal
            )
        )
        let expected = CGSize(
            width: CBPopoverMetrics.width,
            height: (measured.height * 2).rounded(.toNearestOrAwayFromZero) / 2
        )
        let opened = driver.open(
            relativeTo: anchorView.bounds,
            of: anchorView,
            preferredEdge: .maxY
        )
        if opened {
            preflightSizes.append(expected)
            showReturnSizes.append(popover.contentSize)
        }
        return opened
    }

    func requestClose() {
        driver.requestClose()
    }

    func shutdown() {
        driver.shutdown()
        relay.onContentChanged = nil
        relay.onCloseRequested = nil
        popover.delegate = nil
        popover.contentViewController = nil
        anchorWindow?.orderOut(nil)
        anchorWindow?.close()
        host.sizingOptions = []
        host.view.removeFromSuperview()
    }
}

@MainActor
private enum LifecycleWaiter {
    static func until(
        turns: Int = 100,
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<turns {
            if condition() { return true }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return condition()
    }

    static func settle(turns: Int = 10) async {
        for _ in 0..<turns {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}

@Suite(
    "Candidate popover lifecycle characterization",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["CB_RUN_APPKIT_LIFECYCLE_TESTS"] == "1")
)
struct PopoverLifecycleCharacterizationTests {
    @MainActor
    @Test func firstFrameLiveResizeAndHiddenReopenAreConsistent() async throws {
        FontRegistration.registerFonts(searchingFrom: Bundle(for: PopoverLifecycleTestBundleMarker.self).bundleURL)
        let harness = try LifecycleHarness(visibleAnchor: true)
        defer { harness.shutdown() }

        try #require(harness.open())
        #expect(harness.presentationOpenCount == 1)
        #expect(harness.presentationCloseCount == 0)
        let compact = try #require(harness.preflightSizes.last)
        #expect(harness.willShowSizes.last == compact)
        #expect(harness.didShowSizes.last == compact)
        #expect(harness.showReturnSizes.last == compact)
        let writesAfterPreflight = harness.sinkSizes.count
        await LifecycleWaiter.settle()
        #expect(harness.sinkSizes.count == writesAfterPreflight)

        harness.model.usage = PopoverLayoutFixture.expandedUsage()
        try #require(await LifecycleWaiter.until {
            harness.popover.contentSize.height > compact.height + 1
        })
        let expanded = harness.popover.contentSize
        #expect(harness.sinkSizes.last == expanded)

        harness.relay.requestClose()
        try #require(await LifecycleWaiter.until { harness.didCloseCount == 1 })
        #expect(harness.presentationCloseCount == 1)
        let countersWhileClosed = harness.coordinator.debugCounters

        harness.model.usage = PopoverLayoutFixture.compactUsage()
        await LifecycleWaiter.settle()
        #expect(harness.coordinator.debugCounters.scheduledDrains == countersWhileClosed.scheduledDrains)
        #expect(harness.coordinator.debugCounters.drains == countersWhileClosed.drains)
        #expect(harness.coordinator.debugCounters.sinkCalls == countersWhileClosed.sinkCalls)

        try #require(harness.open())
        #expect(harness.presentationOpenCount == 2)
        let reopened = try #require(harness.preflightSizes.last)
        #expect(abs(reopened.height - compact.height) <= 0.5)
        #expect(harness.willShowSizes.last == reopened)
        #expect(harness.didShowSizes.last == reopened)
        #expect(harness.showReturnSizes.last == reopened)
        let writesAfterReopen = harness.sinkSizes.count
        await LifecycleWaiter.settle()
        #expect(harness.sinkSizes.count == writesAfterReopen)

        harness.relay.requestClose()
        try #require(await LifecycleWaiter.until { harness.didCloseCount == 2 })
        #expect(harness.presentationCloseCount == 2)
        #expect(harness.willCloseCount == 2)
        #expect(harness.driver.activeSession == nil)
    }

    @MainActor
    @Test func invisibleAnchorDoesNotStartPresentation() throws {
        let harness = try LifecycleHarness(visibleAnchor: false)
        defer { harness.shutdown() }

        #expect(!harness.open())
        #expect(!harness.popover.isShown)
        #expect(harness.driver.activeSession == nil)
        #expect(harness.presentationOpenCount == 0)
        #expect(harness.presentationCloseCount == 0)
        let scheduled = harness.coordinator.debugCounters.scheduledDrains
        harness.relay.contentChanged()
        #expect(harness.coordinator.debugCounters.scheduledDrains == scheduled)
    }

    @MainActor
    @Test func failedPreflightAbortsAndBalancesPresentation() throws {
        let measurementFailure = try LifecycleHarness(
            visibleAnchor: true,
            measurementSucceeds: false
        )
        defer { measurementFailure.shutdown() }

        #expect(!measurementFailure.open())
        #expect(!measurementFailure.popover.isShown)
        #expect(measurementFailure.presentationOpenCount == 1)
        #expect(measurementFailure.presentationCloseCount == 1)
        #expect(measurementFailure.driver.activeSession == nil)

        let sinkFailure = try LifecycleHarness(
            visibleAnchor: true,
            sinkSucceeds: false
        )
        defer { sinkFailure.shutdown() }

        #expect(!sinkFailure.open())
        #expect(!sinkFailure.popover.isShown)
        #expect(sinkFailure.presentationOpenCount == 1)
        #expect(sinkFailure.presentationCloseCount == 1)
        #expect(sinkFailure.sinkSizes.count == 1)
        #expect(sinkFailure.driver.activeSession == nil)
    }

    @MainActor
    @Test func shutdownFencesPendingLiveResize() async throws {
        let harness = try LifecycleHarness(visibleAnchor: true)
        try #require(harness.open())
        #expect(harness.presentationOpenCount == 1)
        let writes = harness.sinkSizes.count

        harness.model.usage = PopoverLayoutFixture.expandedUsage()
        harness.relay.contentChanged()
        harness.shutdown()
        await LifecycleWaiter.settle()

        #expect(harness.sinkSizes.count == writes)
        #expect(harness.presentationCloseCount == 0)
        #expect(harness.coordinator.beginPresentation() == nil)
    }
}
