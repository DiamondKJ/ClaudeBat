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

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
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
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem.button else {
            NSApp.terminate(nil)
            return
        }

        let hostingView = NSHostingView(rootView: MenuBarLabel(viewModel: viewModel))
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
        popover.contentSize = NSSize(width: 320, height: 392)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: UsagePopoverView(viewModel: viewModel)
        )
        popover.appearance = NSAppearance(named: .darkAqua)
    }

    // MARK: - Context Menu Popover

    private func setupContextPopover() {
        contextPopover = NSPopover()
        contextPopover.behavior = .transient
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
            closeAllPopovers()
            updateContextPopoverContent()
            contextPopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        } else {
            closeAllPopovers()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }

    private func closeAllPopovers() {
        if popover.isShown { popover.performClose(nil) }
        if contextPopover.isShown { contextPopover.performClose(nil) }
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

    private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "ClaudeBat"
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        alert.informativeText = "Your Claude usage. One glance away.\n\nVersion \(version)"
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
