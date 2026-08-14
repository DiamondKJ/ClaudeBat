import SwiftUI
import AppKit
import ServiceManagement
import ClaudeBatCore

@main
struct ClaudeBatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var usageHost: NSHostingController<UsagePopoverView>!
    private var popoverSizeCoordinator: PopoverSizeCoordinator!
    private var popoverPresentationDriver: PopoverPresentationDriver!
    private var contextPopover: NSPopover!
    private let viewModel = UsageViewModel()
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        FontRegistration.registerFonts()
        NSApp.setActivationPolicy(.accessory)

        // Close any restored windows — menu bar only
        NSApp.windows.forEach { $0.close() }

        setupStatusItem()
        setupPopover()
        setupContextPopover()
        setupEventMonitor()
        setupDefaultLaunchAtLogin()
        viewModel.recordAppLaunch()
    }

    func applicationWillTerminate(_ notification: Notification) {
        popoverPresentationDriver?.shutdown()
        viewModel.shutdown()
        viewModel.recordAppTermination()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem.button else {
            NSApp.terminate(nil)
            return
        }

        let hostingView = NSHostingView(rootView: MenuBarLabel(viewModel: viewModel, onTooltipChange: { [weak button] tip in
            button?.toolTip = tip
        }))
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        button.subviews.forEach { $0.removeFromSuperview() }
        button.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 4),
            hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -4),
        ])

        button.action = #selector(statusItemClicked(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    // MARK: - Popover

    private func setupPopover() {
        popover = NSPopover()
        // .applicationDefined (not .transient): we own every open/close so the status
        // button can toggle reliably. .transient auto-closes on the mouse-DOWN before our
        // mouse-UP action runs, which made isShown stale and caused close→reopen flicker
        // when spamming the button. Outside-click closing is handled by the global monitor.
        popover.behavior = .applicationDefined
        // No fade: instant toggle matches the native menu bar feel and removes the
        // animation races that left a phantom popover when clicking rapidly.
        popover.animates = false
        popover.appearance = NSAppearance(named: .darkAqua)

        usageHost = NSHostingController(
            rootView: UsagePopoverView(
                viewModel: viewModel,
                onCloseRequested: { [weak self] in
                    self?.requestUsagePopoverClose()
                },
                onContentInvalidated: { [weak self] in
                    self?.usagePopoverContentInvalidated()
                }
            )
        )
        // Native preferred-size tracking can resize an attached NSPopover behind
        // the coordinator. Keep it disabled and use one finite fitting query.
        usageHost.sizingOptions = []

        popoverSizeCoordinator = PopoverSizeCoordinator(
            width: CBPopoverMetrics.width,
            measure: { [weak host = usageHost] in
                guard let host else { return nil }
                host.view.layoutSubtreeIfNeeded()
                return host.sizeThatFits(
                    in: CGSize(
                        width: CBPopoverMetrics.width,
                        height: CBPopoverMetrics.measurementHeightProposal
                    )
                )
            },
            readCurrentSize: { [weak popover] in
                popover?.contentSize
            },
            applySize: { [weak popover] size in
                guard let popover else { return false }
                popover.contentSize = size
                return popover.contentSize == size
            }
        )

        popoverPresentationDriver = PopoverPresentationDriver(
            popover: popover,
            coordinator: popoverSizeCoordinator,
            onPresentationOpen: { [weak viewModel] in
                viewModel?.onPopoverOpen()
            },
            onPresentationClose: { [weak viewModel] in
                viewModel?.onPopoverClose()
            }
        )

        // Assign last so an early SwiftUI callback can only observe a fully
        // initialized host/coordinator pair.
        popover.contentViewController = usageHost
    }

    // MARK: - Context Menu Popover

    private func setupContextPopover() {
        contextPopover = NSPopover()
        contextPopover.behavior = .applicationDefined
        contextPopover.animates = true
        contextPopover.appearance = NSAppearance(named: .darkAqua)
        updateContextPopoverContent()
    }

    private func updateContextPopoverContent() {
        let isLoginEnabled = UserDefaults.standard.bool(forKey: "launchAtLogin")

        let menuView = RetroContextMenu(
            onToggleLaunchAtLogin: { [weak self] in
                self?.toggleLaunchAtLogin()
                self?.updateContextPopoverContent()
            },
            onOpenUsage: { [weak self] in
                self?.contextPopover.close()
                self?.openManageUsage()
            },
            onAbout: { [weak self] in
                self?.contextPopover.close()
                self?.showAbout()
            },
            onQuit: { NSApp.terminate(nil) },
            launchAtLogin: isLoginEnabled
        )

        let host = NSHostingController(rootView: menuView)
        host.view.wantsLayer = true
        host.view.layer?.backgroundColor = CBNSColor.surface.cgColor
        host.preferredContentSize = NSSize(width: 240, height: 0)
        host.view.setFrameSize(NSSize(width: 240, height: host.view.fittingSize.height))
        contextPopover.contentSize = NSSize(width: 240, height: host.view.fittingSize.height)
        contextPopover.contentViewController = host
    }

    // MARK: - Event Monitor

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closeAllPopovers()
        }
    }

    // MARK: - Actions

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            // Toggle: a second click on the button closes the menu instead of reopening it.
            if contextPopover.isShown {
                contextPopover.performClose(nil)
            } else {
                closeAllPopovers()
                updateContextPopoverContent()
                contextPopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            }
        } else {
            // Toggle: a second click on the button closes the popover instead of reopening it.
            if popover.isShown {
                requestUsagePopoverClose()
            } else {
                closeAllPopovers()
                openUsagePopover(relativeTo: sender)
            }
        }
    }

    private func openUsagePopover(relativeTo sender: NSStatusBarButton) {
        popoverPresentationDriver.open(
            relativeTo: sender.bounds,
            of: sender,
            preferredEdge: .minY
        )
    }

    private func usagePopoverContentInvalidated() {
        popoverPresentationDriver?.contentMayHaveChanged()
    }

    private func requestUsagePopoverClose() {
        popoverPresentationDriver?.requestClose()
    }

    private func closeAllPopovers() {
        if popover.isShown { requestUsagePopoverClose() }
        if contextPopover.isShown { contextPopover.performClose(nil) }
    }

    /// On first launch, opt into Launch at Login by default — a menu-bar app is
    /// expected to persist across reboots. Only acts when the user has never made
    /// a choice (the key is absent); once they toggle it in the context menu, their
    /// preference is respected and this never overrides it.
    private func setupDefaultLaunchAtLogin() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "launchAtLogin") == nil else { return }

        defaults.set(true, forKey: "launchAtLogin")
        if #available(macOS 13.0, *) {
            try? SMAppService.mainApp.register()
        }
    }

    private func toggleLaunchAtLogin() {
        let current = UserDefaults.standard.bool(forKey: "launchAtLogin")
        let newValue = !current
        UserDefaults.standard.set(newValue, forKey: "launchAtLogin")

        if #available(macOS 13.0, *) {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Silently fail — might not be sandboxed or signed
            }
        }
    }

    private func openManageUsage() {
        NSWorkspace.shared.open(CBLinks.manageUsage)
    }

    private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "ClaudeBat"
        var lines = ["Your Claude usage. One glance away."]
        lines.append("")
        lines.append("Tip: ⌘-click and drag the bat to move it to a different spot in the menu bar.")
        lines.append("")
        lines.append("Version \(viewModel.buildInfo.appVersion)")
        if let buildLine = viewModel.buildInfo.aboutBuildLine {
            lines.append(buildLine)
        }
        alert.informativeText = lines.joined(separator: "\n")
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
