//
//  YavenShellController.swift
//  leanring-buddy
//
//  Coordinates the single expanding notch window.
//
//  Architecture:
//  - One YavenNotchWindow lives at the top-centre of the screen.
//  - Collapsed: 250 × 36 pill in the menu bar area.
//  - Expanded: 640 × (36+content) — pill header + full chat panel, growing downward.
//  - YavenNotchExpansion is the shared state; the view and the shell controller
//    both read/write it, while the shell controller resizes the window on changes.
//

import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class YavenShellController: NSObject {

    private enum Layout {
        static let pillWidth: CGFloat          = YavenNotchView.pillWidth
        static let pillHeight: CGFloat         = YavenNotchView.pillHeight
        static let panelWidth: CGFloat         = YavenNotchView.panelWidth
        static let panelContentHeight: CGFloat = YavenNotchView.panelContentHeight
        static let expandedHeight: CGFloat     = YavenNotchView.expandedHeight
        /// NSAnimationContext duration — kept in sync with the SwiftUI notch expansion.
        static let openDuration: TimeInterval  = YavenNotchAnimation.openDuration
        static let closeDuration: TimeInterval = YavenNotchAnimation.closeDuration
        static let ceremonialDuration: TimeInterval = 0.55
    }

    // MARK: - Public surfaces

    let arrivalCoordinator = OnboardingArrivalCoordinator()
    let cleanupController  = YavenCleanupController()

    // MARK: - Private state

    private let expansion            = YavenNotchExpansion()
    private let panelFocusCoordinator = YavenPanelFocusCoordinator()
    private let agentController      = YavenAgentController()
    private let notchWindow          = YavenNotchWindow(
        width: YavenNotchView.panelWidth,
        height: YavenNotchView.pillHeight
    )

    private var arrivalOverlayController: OnboardingArrivalOverlayWindowController?
    private(set) var firstRunPanelMode: YavenFirstRunPanelMode = .hidden

    private var isStarted = false

    private var screenParametersObserver: NSObjectProtocol?
    private var globalClickOutsideMonitor: Any?
    private var localClickOutsideMonitor: Any?
    private var statusItemFrameProvider: (() -> NSRect?)?
    private var spaceYHotkeyMonitor: SpaceYHotkeyMonitor?

    // MARK: - Init

    override init() {
        super.init()

        cleanupController.onSkipped = { [weak self] in
            self?.finishFirstRunFlow()
        }

        // Wire expansion changes → window resize.
        expansion.onExpandedChanged = { [weak self] expanded in
            guard let self else { return }
            if expanded {
                agentController.setPanelVisible(true)
                expandNotchWindow()
            } else {
                collapseNotchWindow()
                agentController.setPanelVisible(false)
                if firstRunPanelMode == .hidden {
                    agentController.cancelAndReset()
                }
            }
        }

        notchWindow.onEscapePressed = { [weak self] in
            self?.expansion.close()
        }

        configureNotchWindow()
        registerScreenChangeObserver()

        YavenNotificationManager.onThreadSelected = { [weak self] threadID in
            guard let self, self.isStarted else { return }
            self.agentController.selectThread(threadID)
            self.openPanel()
        }
    }

    deinit {
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
        }
        if let globalClickOutsideMonitor {
            NSEvent.removeMonitor(globalClickOutsideMonitor)
        }
        if let localClickOutsideMonitor {
            NSEvent.removeMonitor(localClickOutsideMonitor)
        }
    }

    // MARK: - Lifecycle

    func start() {
        isStarted = true
        registerSpaceYHotkey()
        positionNotchWindow()
        notchWindow.orderFrontRegardless()
    }

    func startFirstRunExperienceIfNeeded(
        clickOrigin: CGPoint = .zero,
        appearance: OnboardingAppearance = .cloud
    ) {
        positionNotchWindow()
        notchWindow.orderFrontRegardless()

        guard OnboardingManager.shouldRunFirstRunArrival else {
            arrivalCoordinator.orbScale = 1
            arrivalCoordinator.orbOpacity = 1
            return
        }

        arrivalCoordinator.orbScale = 0.5
        arrivalCoordinator.orbOpacity = 0
        arrivalCoordinator.clickOrigin = clickOrigin
        arrivalCoordinator.selectedAppearance = appearance

        arrivalOverlayController = OnboardingArrivalOverlayWindowController(
            coordinator: arrivalCoordinator,
            orbFrameProvider: { [weak self] in
                self?.notchWindow.frame ?? .zero
            }
        )
        arrivalOverlayController?.show()

        arrivalCoordinator.onPanelSummon = { [weak self] in
            self?.openPanelCeremonial()
        }
        arrivalCoordinator.onSequenceFinished = { [weak self] in
            self?.arrivalOverlayController?.dismiss()
            self?.arrivalOverlayController = nil
            OnboardingManager.clearFirstRunArrivalFlag()
        }

        arrivalCoordinator.startOrbBloom()
    }

    func setStatusItemFrameProvider(_ provider: @escaping () -> NSRect?) {
        self.statusItemFrameProvider = provider
    }

    // MARK: - Panel open/close

    func togglePanel() {
        guard isStarted else { return }
        if expansion.isExpanded { expansion.close() } else { expansion.open() }
    }

    func showPanel() {
        guard isStarted else { return }
        openPanel()
    }

    func showPanelCeremonial() {
        guard isStarted else { return }
        openPanelCeremonial()
    }

    func hidePanel() {
        guard isStarted else { return }
        expansion.close()
    }

    // MARK: - First-run flow

    func beginInboxCleanupFlow() {
        arrivalCoordinator.userChoseCleanup()
        firstRunPanelMode = .cleanup
        refreshNotchContent()
        let entityId = OnboardingManager.savedEntityId ?? ""
        cleanupController.start(entityId: entityId)
    }

    func dismissFirstRunFlow() {
        arrivalCoordinator.userChoseLater()
        firstRunPanelMode = .hidden
        refreshNotchContent()
        expansion.close()
    }

    func finishFirstRunFlow() {
        firstRunPanelMode = .hidden
        refreshNotchContent()
    }

    func draftReplyFromCleanup(_ item: NeedsReplyItem) {
        let encodedTo = item.sender.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let replySubject = item.subject.hasPrefix("Re:") ? item.subject : "Re: \(item.subject)"
        let encodedSubject = replySubject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://mail.google.com/mail/u/0/?view=cm&fs=1&to=\(encodedTo)&su=\(encodedSubject)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Window setup

    private func configureNotchWindow() {
        let notchView = makeNotchView()
        let hostingView = NSHostingView(rootView: notchView)
        hostingView.frame = NSRect(x: 0, y: 0, width: Layout.panelWidth, height: Layout.pillHeight)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        notchWindow.contentView = hostingView
    }

    private func makeNotchView() -> YavenNotchView {
        YavenNotchView(
            expansion: expansion,
            agentController: agentController,
            arrivalCoordinator: arrivalCoordinator,
            focusCoordinator: panelFocusCoordinator,
            cleanupController: cleanupController,
            firstRunPanelMode: firstRunPanelMode,
            onPreferredHeightChange: { [weak self] preferredHeight in
                self?.handlePreferredHeightChange(preferredHeight)
            },
            onFirstRunYes: { [weak self] in
                self?.beginInboxCleanupFlow()
            },
            onFirstRunLater: { [weak self] in
                self?.dismissFirstRunFlow()
            },
            onCleanupSkip: { [weak self] in
                self?.cleanupController.skip()
                self?.finishFirstRunFlow()
            },
            onCleanupContinue: { [weak self] in
                self?.finishFirstRunFlow()
                self?.panelFocusCoordinator.requestInputFocus()
            },
            onDraftReply: { [weak self] item in
                self?.draftReplyFromCleanup(item)
            }
        )
    }

    /// Rebuilds the hosting view's root when firstRunPanelMode changes.
    private func refreshNotchContent() {
        guard let hostingView = notchWindow.contentView as? NSHostingView<YavenNotchView> else { return }
        hostingView.rootView = makeNotchView()
    }

    // MARK: - Frame helpers

    private func collapsedFrame() -> NSRect {
        // screens.first is always the primary/menu-bar screen.
        // Width is always panelWidth so the window never shifts left/right on expand/collapse.
        let screen = NSScreen.screens.first?.frame ?? NSScreen.main?.frame ?? .zero
        return NSRect(
            x: screen.midX - Layout.panelWidth / 2,
            y: screen.maxY - Layout.pillHeight,
            width: Layout.panelWidth,
            height: Layout.pillHeight
        )
    }

    private func expandedFrame(panelContentHeight: CGFloat = Layout.panelContentHeight) -> NSRect {
        let totalHeight = Layout.pillHeight + panelContentHeight
        let screen = NSScreen.screens.first?.frame ?? NSScreen.main?.frame ?? .zero
        return NSRect(
            x: screen.midX - Layout.panelWidth / 2,
            y: screen.maxY - totalHeight,
            width: Layout.panelWidth,
            height: totalHeight
        )
    }

    private func positionNotchWindow() {
        let frame = expansion.isExpanded ? expandedFrame() : collapsedFrame()
        notchWindow.setFrame(frame, display: true)
    }

    // MARK: - Window animations

    private func expandNotchWindow() {
        // Set frame instantly — SwiftUI spring drives all visible animation, exactly like boring.notch.
        // Animating the NSWindow frame concurrently with SwiftUI causes the jump/gap artefact.
        notchWindow.setFrame(expandedFrame(), display: true)
        notchWindow.makeKeyAndOrderFront(nil)
        notchWindow.makeKey()
        installClickOutsideMonitors()
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Layout.openDuration * 1_000_000_000))
            self?.panelFocusCoordinator.requestInputFocus()
        }
    }

    private func collapseNotchWindow() {
        notchWindow.setFrame(collapsedFrame(), display: true)
        removeClickOutsideMonitors()
    }

    private func handlePreferredHeightChange(_ preferredHeight: CGFloat) {
        guard expansion.isExpanded else { return }
        let targetFrame = expandedFrame(panelContentHeight: preferredHeight)
        guard abs(targetFrame.height - notchWindow.frame.height) > 2
           || abs(targetFrame.width  - notchWindow.frame.width)  > 2 else { return }
        notchWindow.setFrame(targetFrame, display: true)
    }

    // MARK: - Private open helpers

    private func openPanel() {
        guard !expansion.isExpanded else {
            panelFocusCoordinator.requestInputFocus()
            return
        }
        expansion.open()
    }

    private func openPanelCeremonial() {
        firstRunPanelMode = .firstMessage
        refreshNotchContent()
        if !expansion.isExpanded {
            notchWindow.setFrame(expandedFrame(), display: true)
        }
        withAnimation(.easeInOut(duration: Layout.ceremonialDuration)) {
            expansion.open()
        }
    }

    // MARK: - Observers

    private func registerScreenChangeObserver() {
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in self.positionNotchWindow() }
        }
    }

    private func registerSpaceYHotkey() {
        spaceYHotkeyMonitor = SpaceYHotkeyMonitor { [weak self] in
            guard let self else { return }
            Task { @MainActor [self] in self.togglePanel() }
        }
    }

    // MARK: - Click-outside monitors

    private func installClickOutsideMonitors() {
        removeClickOutsideMonitors()

        globalClickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            let location = NSEvent.mouseLocation
            Task { @MainActor in
                self?.hidePanelIfClickIsOutside(at: location)
            }
        }

        localClickOutsideMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            let location = NSEvent.mouseLocation
            Task { @MainActor in
                self?.hidePanelIfClickIsOutside(at: location)
            }
            return event
        }
    }

    private func removeClickOutsideMonitors() {
        if let globalClickOutsideMonitor {
            NSEvent.removeMonitor(globalClickOutsideMonitor)
            self.globalClickOutsideMonitor = nil
        }
        if let localClickOutsideMonitor {
            NSEvent.removeMonitor(localClickOutsideMonitor)
            self.localClickOutsideMonitor = nil
        }
    }

    private func hidePanelIfClickIsOutside(at clickLocation: NSPoint) {
        guard expansion.isExpanded else { return }
        guard firstRunPanelMode == .hidden else { return }
        guard !notchWindow.frame.contains(clickLocation) else { return }
        if let statusItemFrame = statusItemFrameProvider?(), statusItemFrame.contains(clickLocation) {
            return
        }
        withAnimation(YavenNotchAnimation.close) {
            expansion.close()
        }
    }
}
