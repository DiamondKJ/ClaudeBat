import AppKit

/// Owns the usage popover's open/close session transaction. AppDelegate and
/// the synthetic AppKit lifecycle harness both use this exact implementation.
@MainActor
public final class PopoverPresentationDriver: NSObject, NSPopoverDelegate {
    public typealias LifecycleCallback = @MainActor @Sendable () -> Void

    private let popover: NSPopover
    private let coordinator: PopoverSizeCoordinator
    private let onPresentationOpen: LifecycleCallback
    private let onPresentationClose: LifecycleCallback
    private let onWillShowSize: (@MainActor (CGSize) -> Void)?
    private let onDidShowSize: (@MainActor (CGSize) -> Void)?
    private let onWillClose: LifecycleCallback?
    private let onDidClose: LifecycleCallback?

    private(set) var activeSession: PopoverSizeCoordinator.Session?
    private(set) var closingSession: PopoverSizeCoordinator.Session?
    private(set) var presentationOpen = false
    private(set) var isTerminating = false

    public init(
        popover: NSPopover,
        coordinator: PopoverSizeCoordinator,
        onPresentationOpen: @escaping LifecycleCallback,
        onPresentationClose: @escaping LifecycleCallback
    ) {
        self.popover = popover
        self.coordinator = coordinator
        self.onPresentationOpen = onPresentationOpen
        self.onPresentationClose = onPresentationClose
        self.onWillShowSize = nil
        self.onDidShowSize = nil
        self.onWillClose = nil
        self.onDidClose = nil
        super.init()
        popover.delegate = self
    }

    init(
        popover: NSPopover,
        coordinator: PopoverSizeCoordinator,
        onPresentationOpen: @escaping LifecycleCallback,
        onPresentationClose: @escaping LifecycleCallback,
        onWillShowSize: (@MainActor (CGSize) -> Void)?,
        onDidShowSize: (@MainActor (CGSize) -> Void)?,
        onWillClose: LifecycleCallback?,
        onDidClose: LifecycleCallback?
    ) {
        self.popover = popover
        self.coordinator = coordinator
        self.onPresentationOpen = onPresentationOpen
        self.onPresentationClose = onPresentationClose
        self.onWillShowSize = onWillShowSize
        self.onDidShowSize = onDidShowSize
        self.onWillClose = onWillClose
        self.onDidClose = onDidClose
        super.init()
        popover.delegate = self
    }

    @discardableResult
    public func open(
        relativeTo positioningRect: NSRect,
        of positioningView: NSView,
        preferredEdge: NSRectEdge
    ) -> Bool {
        guard !isTerminating,
              !presentationOpen,
              positioningView.window != nil,
              positioningView.window?.isVisible == true else { return false }

        onPresentationOpen()
        presentationOpen = true

        guard let session = coordinator.beginPresentation() else {
            balanceFailedOpen()
            return false
        }
        activeSession = session

        guard coordinator.prepareForShow(in: session) else {
            abortOpen(session)
            return false
        }

        popover.show(
            relativeTo: positioningRect,
            of: positioningView,
            preferredEdge: preferredEdge
        )
        guard popover.isShown else {
            abortOpen(session)
            return false
        }

        coordinator.markShown(in: session)
        return true
    }

    public func contentMayHaveChanged() {
        guard let activeSession else { return }
        coordinator.contentMayHaveChanged(in: activeSession)
    }

    public func requestClose() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let activeSession {
            coordinator.endPresentation(activeSession)
            self.activeSession = nil
            balanceFailedOpen()
        }
    }

    public func shutdown() {
        guard !isTerminating else { return }
        isTerminating = true
        coordinator.shutdown()
        activeSession = nil
        closingSession = nil
        presentationOpen = false
        if popover.isShown {
            popover.performClose(nil)
        }
    }

    public func popoverWillShow(_ notification: Notification) {
        guard notification.object as? NSPopover === popover else { return }
        onWillShowSize?(popover.contentSize)
    }

    public func popoverDidShow(_ notification: Notification) {
        guard notification.object as? NSPopover === popover else { return }
        onDidShowSize?(popover.contentSize)
    }

    public func popoverWillClose(_ notification: Notification) {
        guard notification.object as? NSPopover === popover,
              let activeSession else { return }
        onWillClose?()
        self.activeSession = nil
        closingSession = activeSession
        coordinator.endPresentation(activeSession)
    }

    public func popoverDidClose(_ notification: Notification) {
        guard notification.object as? NSPopover === popover else { return }
        onDidClose?()
        closingSession = nil
        guard !isTerminating, presentationOpen else { return }
        presentationOpen = false
        onPresentationClose()
    }

    private func abortOpen(_ session: PopoverSizeCoordinator.Session) {
        coordinator.endPresentation(session)
        if activeSession == session {
            activeSession = nil
        }
        balanceFailedOpen()
    }

    private func balanceFailedOpen() {
        guard presentationOpen else { return }
        presentationOpen = false
        onPresentationClose()
    }
}
