//
//  MenuBarPanelManager.swift
//  leanring-buddy
//
//  Manages the NSStatusItem fallback entrypoint for the Yaven shell.
//

import AppKit

extension Notification.Name {
    static let clickyDismissPanel = Notification.Name("clickyDismissPanel")
}

@MainActor
final class MenuBarPanelManager: NSObject {
    private var statusItem: NSStatusItem?
    private weak var shellController: YavenShellController?

    init(shellController: YavenShellController) {
        self.shellController = shellController
        super.init()
        createStatusItem()
    }

    // MARK: - Status Item

    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else { return }

        button.title = "Yaven"
        button.action = #selector(statusItemClicked)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        shellController?.setStatusItemFrameProvider { [weak self] in
            self?.statusItem?.button?.window?.frame
        }
    }

    @objc private func statusItemClicked() {
        if shouldShowQuitMenu(for: NSApp.currentEvent) {
            showQuitMenu()
            return
        }

        shellController?.togglePanel()
    }

    private func shouldShowQuitMenu(for event: NSEvent?) -> Bool {
        event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
    }

    private func showQuitMenu() {
        guard let button = statusItem?.button else { return }

        let menu = NSMenu()
        let quitMenuItem = NSMenuItem(title: "Quit Yaven", action: #selector(quitYaven), keyEquivalent: "q")
        quitMenuItem.target = self
        menu.addItem(quitMenuItem)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }

    @objc private func quitYaven() {
        NSApp.terminate(nil)
    }
}
